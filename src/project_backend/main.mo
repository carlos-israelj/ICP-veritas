import Debug "mo:base/Debug";
import Text "mo:base/Text";
import Time "mo:base/Time";
import Int "mo:base/Int";
import Result "mo:base/Result";
import Blob "mo:base/Blob";
import Cycles "mo:base/ExperimentalCycles";

actor NewsFactChecker {
    
    // Configuración de la API de Perplexity
    private let PERPLEXITY_API_URL = "https://api.perplexity.ai/chat/completions";
    private let API_KEY = "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";
    
    // Tipos para HTTP outcalls nativos de ICP
    public type HttpHeader = {
        name: Text;
        value: Text;
    };

    public type HttpMethod = {
        #get;
        #post;
        #head;
    };

    public type HttpRequest = {
        url: Text;
        max_response_bytes: ?Nat64;
        headers: [HttpHeader];
        body: ?[Nat8];
        method: HttpMethod;
        transform: ?{
            #function: (shared query {
                response: HttpResponse;
                context: Blob;
            } -> async HttpResponse);
        };
    };

    public type HttpResponse = {
        status: Nat;
        headers: [HttpHeader];
        body: [Nat8];
    };

    // Tipo para almacenar el resultado del análisis completo
    public type AnalysisResult = {
        isReliable: Bool;
        confidence: Float;
        summary: Text;
        sources: [Text];
        timestamp: Int;
        reasoning: Text;
        context: Text;
        consistency: Text;
        recommendations: Text;
        verificationStatus: Text;
    };

    // Tipo para errores
    public type ApiError = {
        #NetworkError: Text;
        #InvalidInput: Text;
        #ApiError: Text;
        #ParseError: Text;
    };

    // Función principal para analizar noticias usando Perplexity
    public func analyzeNews(newsText: Text) : async Result.Result<AnalysisResult, ApiError> {
        
        // Validar entrada
        if (Text.size(newsText) == 0) {
            return #err(#InvalidInput("El texto de la noticia no puede estar vacío"));
        };
        
        if (Text.size(newsText) > 4000) {
            return #err(#InvalidInput("El texto es demasiado largo (máximo 4000 caracteres)"));
        };

        // Llamar a la API de Perplexity
        switch (await callPerplexityAPI(newsText)) {
            case (#ok(response)) {
                // Parsear y analizar la respuesta
                switch (parsePerplexityResponse(response, newsText)) {
                    case (#ok(analysis)) {
                        let result: AnalysisResult = {
                            isReliable = analysis.isReliable;
                            confidence = analysis.confidence;
                            summary = analysis.summary;
                            sources = analysis.sources;
                            reasoning = analysis.reasoning;
                            context = analysis.context;
                            consistency = analysis.consistency;
                            recommendations = analysis.recommendations;
                            verificationStatus = analysis.verificationStatus;
                            timestamp = Time.now();
                        };
                        #ok(result)
                    };
                    case (#err(parseError)) {
                        #err(parseError)
                    };
                }
            };
            case (#err(apiError)) {
                // Si falla la API, usar análisis local como fallback
                let fallbackAnalysis = performLocalAnalysis(newsText);
                let result: AnalysisResult = {
                    isReliable = fallbackAnalysis.isReliable;
                    confidence = fallbackAnalysis.confidence;
                    summary = "⚠️ Análisis local (API no disponible): " # fallbackAnalysis.summary;
                    sources = fallbackAnalysis.sources;
                    reasoning = "Análisis realizado localmente debido a: " # errorToText(apiError);
                    context = "Análisis básico por palabras clave";
                    consistency = "Análisis simplificado sin acceso a fuentes externas";
                    recommendations = "Se recomienda verificar con fuentes oficiales cuando la API esté disponible";
                    verificationStatus = if (fallbackAnalysis.isReliable) "No Verificado" else "Impreciso";
                    timestamp = Time.now();
                };
                #ok(result)
            };
        }
    };

    // Función para llamar a la API de Perplexity
    private func callPerplexityAPI(newsText: Text) : async Result.Result<Text, ApiError> {
        
        Debug.print("Iniciando llamada a Perplexity API...");
        
        // Verificar API key
        if (API_KEY == "YOUR_PERPLEXITY_API_KEY") {
            Debug.print("ERROR: API key no configurada");
            return #err(#ApiError("API key no configurada"));
        };
        
        let cleanText = escapeJson(newsText);
        let systemPrompt = "Eres un verificador de noticias especializado en elecciones de Ecuador 2025.";
        
        let userPrompt = "Actúa como un verificador de noticias especializado en elecciones de Ecuador 2025. " #
            "Analiza cuidadosamente el siguiente contenido: " # cleanText # " " #
            "Por favor, verifica la veracidad de esta información considerando: " #
            "1. Hechos verificables vs opiniones " #
            "2. Fuentes oficiales electorales de Ecuador " #
            "3. Contradicciones o inconsistencias " #
            "4. Contexto completo de la información " #
            "5. Posibles sesgos o manipulación " #
            "Responde EXCLUSIVAMENTE en formato JSON con la siguiente estructura exacta: " #
            "{" #
                "\\\"resultado\\\": \\\"[RESULTADO]\\\", " #
                "\\\"resumen\\\": \\\"[RESUMEN CONCISO DEL CONTENIDO ANALIZADO Y SU CONTEXTO]\\\", " #
                "\\\"evidencia\\\": \\\"[ANÁLISIS DE EVIDENCIA DISPONIBLE]\\\", " #
                "\\\"contexto\\\": \\\"[ANÁLISIS DEL CONTEXTO]\\\", " #
                "\\\"fuentes_consultadas\\\": \\\"[FUENTES CONSULTADAS RELACIONADAS CON LA CONSULTA]\\\", " #
                "\\\"consistencia\\\": \\\"[ANÁLISIS DE CONSISTENCIA DE LA INFORMACIÓN]\\\", " #
                "\\\"recomendaciones\\\": \\\"[3-5 RECOMENDACIONES PARA EL LECTOR]\\\", " #
                "\\\"confianza\\\": [NÚMERO ENTRE 0.0 Y 1.0] " #
            "} " #
            "Para el campo resultado, usa EXCLUSIVAMENTE una de estas opciones: " #
            "Verificado (si la información es confirmada por fuentes confiables), " #
            "Impreciso (si la información contiene algunos datos correctos pero otros incorrectos), " #
            "No Verificado (si no hay suficiente evidencia para confirmar o negar), " #
            "Falso (si la información es claramente incorrecta). " #
            "IMPORTANTE: Responde SOLO con el JSON, sin texto adicional antes o después.";

        let requestBody = "{" #
            "\"model\": \"sonar\"," #
            "\"messages\": [" #
                "{\"role\": \"system\", \"content\": \"" # escapeJson(systemPrompt) # "\"}," #
                "{\"role\": \"user\", \"content\": \"" # escapeJson(userPrompt) # "\"}" #
            "]," #
            "\"max_tokens\": 1024," #
            "\"temperature\": 0.7" #
        "}";

        let headers = [
            { name = "Authorization"; value = "Bearer " # API_KEY },
            { name = "Content-Type"; value = "application/json" },
            { name = "Accept"; value = "application/json" }
        ];

        let bodyBytes = Blob.toArray(Text.encodeUtf8(requestBody));
        let request : HttpRequest = {
            url = PERPLEXITY_API_URL;
            max_response_bytes = ?2000000;
            headers = headers;
            body = ?bodyBytes;
            method = #post;
            transform = null;
        };

        Cycles.add(230_000_000_000);

        try {
            let ic : actor {
                http_request : HttpRequest -> async HttpResponse;
            } = actor("aaaaa-aa");
            
            let response = await ic.http_request(request);
            
            switch (response.status) {
                case (200) {
                    switch (Text.decodeUtf8(Blob.fromArray(response.body))) {
                        case (?text) { #ok(text) };
                        case null { #err(#ParseError("No se pudo decodificar la respuesta")) };
                    }
                };
                case (401) { #err(#ApiError("Error de autenticación")) };
                case (429) { #err(#ApiError("Límite de rate excedido")) };
                case (code) { #err(#ApiError("Error de API: " # Int.toText(code))) };
            }
        } catch (error) {
            #err(#NetworkError("Error de red"))
        }
    };

    // Función para parsear la respuesta de Perplexity
    private func parsePerplexityResponse(response: Text, originalText: Text) : Result.Result<{
        isReliable: Bool;
        confidence: Float;
        summary: Text;
        sources: [Text];
        reasoning: Text;
        context: Text;
        consistency: Text;
        recommendations: Text;
        verificationStatus: Text;
    }, ApiError> {
        
        let content = extractContentFromResponse(response);
        let analysis = parseAnalysisFromContent(content);
        
        switch (analysis) {
            case (?result) { #ok(result) };
            case null { 
                let fallbackAnalysis = performLocalAnalysis(originalText);
                #ok({
                    isReliable = fallbackAnalysis.isReliable;
                    confidence = fallbackAnalysis.confidence;
                    summary = fallbackAnalysis.summary;
                    sources = fallbackAnalysis.sources;
                    reasoning = "Análisis local (fallo en parsing de API)";
                    context = "Análisis básico sin acceso completo a la API";
                    consistency = "Análisis simplificado";
                    recommendations = "Verificar con fuentes oficiales";
                    verificationStatus = if (fallbackAnalysis.isReliable) "No Verificado" else "Impreciso";
                })
            };
        }
    };

    // Extraer contenido de la respuesta
    private func extractContentFromResponse(response: Text) : Text {
        if (Text.contains(response, #text "\"content\":\"")) {
            let parts = Text.split(response, #text "\"content\":\"");
            switch (parts.next()) {
                case (?_) {
                    switch (parts.next()) {
                        case (?contentPart) {
                            if (Text.contains(contentPart, #text "\"}")) {
                                let endParts = Text.split(contentPart, #text "\"}");
                                switch (endParts.next()) {
                                    case (?rawContent) { unescapeJson(rawContent) };
                                    case null { unescapeJson(contentPart) };
                                }
                            } else {
                                unescapeJson(contentPart)
                            }
                        };
                        case null { response };
                    }
                };
                case null { response };
            }
        } else {
            response
        }
    };

    // PARSING MEJORADO DE ANÁLISIS CON CONFIANZA CORREGIDA
    private func parseAnalysisFromContent(content: Text) : ?{
        isReliable: Bool;
        confidence: Float;
        summary: Text;
        sources: [Text];
        reasoning: Text;
        context: Text;
        consistency: Text;
        recommendations: Text;
        verificationStatus: Text;
    } {
        
        Debug.print("Parseando contenido: " # content);
        
        var jsonContent = content;
        if (Text.contains(content, #text "```json")) {
            let parts = Text.split(content, #text "```json");
            switch (parts.next()) {
                case (?_) {
                    switch (parts.next()) {
                        case (?jsonPart) {
                            if (Text.contains(jsonPart, #text "```")) {
                                let endParts = Text.split(jsonPart, #text "```");
                                switch (endParts.next()) {
                                    case (?extractedJson) {
                                        jsonContent := Text.trim(extractedJson, #text " \n\r\t");
                                    };
                                    case null {};
                                }
                            };
                        };
                        case null {};
                    }
                };
                case null {};
            }
        };
        
        let cleanedJson = Text.replace(Text.replace(Text.replace(jsonContent, #text "\n", ""), #text "\r", ""), #text "  ", " ");
        Debug.print("JSON limpio: " # cleanedJson);
        
        // Extraer resultado
        var verificationStatus = "No Verificado";
        var isReliable = false;
        
        if (Text.contains(cleanedJson, #text "\"resultado\": \"Verificado\"") or 
            Text.contains(cleanedJson, #text "\"resultado\":\"Verificado\"")) {
            verificationStatus := "Verificado";
            isReliable := true;
        } else if (Text.contains(cleanedJson, #text "\"resultado\": \"Impreciso\"") or 
                   Text.contains(cleanedJson, #text "\"resultado\":\"Impreciso\"")) {
            verificationStatus := "Impreciso";
            isReliable := false;
        } else if (Text.contains(cleanedJson, #text "\"resultado\": \"Falso\"") or 
                   Text.contains(cleanedJson, #text "\"resultado\":\"Falso\"")) {
            verificationStatus := "Falso";
            isReliable := false;
        };
        
        // EXTRACCIÓN DE CONFIANZA MEJORADA
        var confidence: Float = 0.5;
        
        // Buscar patrón "confianza": 0.XX
        if (Text.contains(cleanedJson, #text "\"confianza\": ")) {
            let parts = Text.split(cleanedJson, #text "\"confianza\": ");
            switch (parts.next()) {
                case (?_) {
                    switch (parts.next()) {
                        case (?confidencePart) {
                            let numberText = extractNumberFromText(confidencePart);
                            confidence := parseFloatFromText(numberText);
                            Debug.print("✅ Confianza encontrada: " # numberText);
                        };
                        case null {};
                    }
                };
                case null {};
            }
        } else if (Text.contains(cleanedJson, #text "\"confianza\":")) {
            let parts = Text.split(cleanedJson, #text "\"confianza\":");
            switch (parts.next()) {
                case (?_) {
                    switch (parts.next()) {
                        case (?confidencePart) {
                            let numberText = extractNumberFromText(confidencePart);
                            confidence := parseFloatFromText(numberText);
                            Debug.print("✅ Confianza encontrada: " # numberText);
                        };
                        case null {};
                    }
                };
                case null {};
            }
        } else {
            // Asignar por defecto basado en resultado
            confidence := switch (verificationStatus) {
                case ("Verificado") { 0.8 };
                case ("Impreciso") { 0.5 };
                case ("Falso") { 0.2 };
                case (_) { 0.4 };
            };
        };
        
        let summary = extractJsonField(cleanedJson, "resumen", "Análisis completado por IA");
        let reasoning = extractJsonField(cleanedJson, "evidencia", "Análisis de evidencia disponible");
        let context = extractJsonField(cleanedJson, "contexto", "Análisis del contexto");
        let consistency = extractJsonField(cleanedJson, "consistencia", "Análisis de consistencia");
        let recommendations = extractJsonField(cleanedJson, "recomendaciones", "Verificar con fuentes oficiales");
        let sourcesText = extractJsonField(cleanedJson, "fuentes_consultadas", "Consejo Nacional Electoral, Registraduría Nacional");
        
        let sources = [
            sourcesText,
            "Misión de Observación Electoral",
            "Análisis verificado por Perplexity AI"
        ];
        
        Debug.print("Parsing completado - Status: " # verificationStatus # ", Confianza: " # floatToText(confidence));
        
        ?{
            isReliable = isReliable;
            confidence = confidence;
            summary = summary;
            sources = sources;
            reasoning = reasoning;
            context = context;
            consistency = consistency;
            recommendations = recommendations;
            verificationStatus = verificationStatus;
        }
    };

    // Extraer número del texto
    private func extractNumberFromText(text: Text) : Text {
        if (Text.contains(text, #text ",")) {
            let parts = Text.split(text, #text ",");
            switch (parts.next()) {
                case (?numberPart) { Text.trim(numberPart, #text " \n\r\t") };
                case null { "" };
            }
        } else if (Text.contains(text, #text "}")) {
            let parts = Text.split(text, #text "}");
            switch (parts.next()) {
                case (?numberPart) { Text.trim(numberPart, #text " \n\r\t") };
                case null { "" };
            }
        } else {
            Text.trim(text, #text " \n\r\t")
        }
    };

    // Convertir texto a Float
    private func parseFloatFromText(text: Text) : Float {
        switch (text) {
            case ("0.0") { 0.0 };
            case ("0.1") { 0.1 };
            case ("0.2") { 0.2 };
            case ("0.3") { 0.3 };
            case ("0.4") { 0.4 };
            case ("0.5") { 0.5 };
            case ("0.6") { 0.6 };
            case ("0.7") { 0.7 };
            case ("0.8") { 0.8 };
            case ("0.9") { 0.9 };
            case ("0.95") { 0.95 };
            case ("0.97") { 0.97 };
            case ("0.98") { 0.98 };
            case ("0.99") { 0.99 };
            case ("1.0") { 1.0 };
            case ("1") { 1.0 };
            case (_) { 0.5 };
        }
    };

    // Extraer campo JSON
    private func extractJsonField(jsonText: Text, fieldName: Text, defaultValue: Text) : Text {
        let pattern = "\"" # fieldName # "\": \"";
        if (Text.contains(jsonText, #text pattern)) {
            let parts = Text.split(jsonText, #text pattern);
            switch (parts.next()) {
                case (?_) {
                    switch (parts.next()) {
                        case (?fieldPart) {
                            if (Text.contains(fieldPart, #text "\",")) {
                                let endParts = Text.split(fieldPart, #text "\",");
                                switch (endParts.next()) {
                                    case (?extractedField) {
                                        if (Text.size(extractedField) > 0) {
                                            return extractedField;
                                        };
                                    };
                                    case null {};
                                }
                            };
                        };
                        case null {};
                    }
                };
                case null {};
            }
        };
        defaultValue
    };

    // Análisis local como fallback
    private func performLocalAnalysis(text: Text) : {
        isReliable: Bool;
        confidence: Float;
        summary: Text;
        sources: [Text];
    } {
        let lowerText = Text.toLowercase(text);
        
        let suspiciousKeywords = [
            "fraude electoral masivo", "elecciones robadas", "votos ilegales",
            "manipulación de urnas", "sistema comprometido", "conspiración electoral"
        ];
        
        let reliableKeywords = [
            "según organismos electorales", "confirmado por autoridades",
            "datos oficiales", "estudio verificado", "fuentes oficiales"
        ];
        
        var suspiciousCount = 0;
        var reliableCount = 0;
        
        for (keyword in suspiciousKeywords.vals()) {
            if (Text.contains(lowerText, #text keyword)) {
                suspiciousCount += 1;
            };
        };
        
        for (keyword in reliableKeywords.vals()) {
            if (Text.contains(lowerText, #text keyword)) {
                reliableCount += 1;
            };
        };
        
        let isReliable = suspiciousCount <= reliableCount;
        let confidence = if (suspiciousCount == 0 and reliableCount > 0) {
            0.8
        } else if (suspiciousCount == 0) {
            0.6
        } else if (reliableCount > suspiciousCount) {
            0.4
        } else {
            0.2
        };
        
        let summary = if (suspiciousCount > reliableCount) {
            "⚠️ La noticia contiene indicadores de posible desinformación electoral"
        } else if (reliableCount > 0) {
            "✅ La noticia parece contener información de fuentes confiables"
        } else {
            "ℹ️ Se requiere verificación adicional con fuentes oficiales"
        };
        
        {
            isReliable = isReliable;
            confidence = confidence;
            summary = summary;
            sources = ["Consejo Nacional Electoral", "Registraduría Nacional"];
        }
    };

    // Funciones auxiliares
    private func escapeJson(text: Text) : Text {
        let escaped1 = Text.replace(text, #text "\\", "\\\\");
        let escaped2 = Text.replace(escaped1, #text "\"", "\\\"");
        let escaped3 = Text.replace(escaped2, #text "\n", "\\n");
        Text.replace(escaped3, #text "\r", "\\r")
    };

    private func unescapeJson(text: Text) : Text {
        let unescaped1 = Text.replace(text, #text "\\\"", "\"");
        let unescaped2 = Text.replace(unescaped1, #text "\\n", "\n");
        let unescaped3 = Text.replace(unescaped2, #text "\\r", "\r");
        Text.replace(unescaped3, #text "\\\\", "\\")
    };

    private func errorToText(error: ApiError) : Text {
        switch (error) {
            case (#NetworkError(msg)) { "Error de red: " # msg };
            case (#InvalidInput(msg)) { "Entrada inválida: " # msg };
            case (#ApiError(msg)) { "Error de API: " # msg };
            case (#ParseError(msg)) { "Error de parsing: " # msg };
        }
    };

    private func floatToText(f: Float) : Text {
        if (f == 0.0) "0.0"
        else if (f == 0.1) "0.1"
        else if (f == 0.2) "0.2"
        else if (f == 0.3) "0.3"
        else if (f == 0.4) "0.4"
        else if (f == 0.5) "0.5"
        else if (f == 0.6) "0.6"
        else if (f == 0.7) "0.7"
        else if (f == 0.8) "0.8"
        else if (f == 0.9) "0.9"
        else if (f == 0.95) "0.95"
        else if (f == 0.97) "0.97"
        else if (f == 0.98) "0.98"
        else if (f == 0.99) "0.99"
        else if (f == 1.0) "1.0"
        else "unknown"
    };

    // Funciones públicas
    public query func greet(name : Text) : async Text {
        "¡Hola, " # name # "! Bienvenido al verificador de noticias electorales con IA."
    };

    public query func getSystemInfo() : async {
        version: Text;
        supportedLanguages: [Text];
        maxTextLength: Nat;
        apiProvider: Text;
    } {
        {
            version = "3.0.0";
            supportedLanguages = ["Español", "English"];
            maxTextLength = 4000;
            apiProvider = "Perplexity AI + Local Fallback";
        }
    };

    public func testApiConnection() : async Result.Result<Text, ApiError> {
        await callPerplexityAPI("Test de conectividad")
    };
}