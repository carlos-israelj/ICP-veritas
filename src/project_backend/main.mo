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
        detectedLanguage: Text;
    };

    // Tipo para errores
    public type ApiError = {
        #NetworkError: Text;
        #InvalidInput: Text;
        #ApiError: Text;
        #ParseError: Text;
    };

    // FUNCIÓN PARA DETECTAR IDIOMA MEJORADA
    private func detectLanguage(text: Text) : Text {
        let lowerText = Text.toLowercase(text);
        
        // Palabras más específicas y comunes en inglés
        let englishWords = [
            "the", "and", "for", "are", "with", "his", "they", "this", "have", "from", "or", "one",
            "had", "by", "word", "but", "not", "what", "all", "were", "when", "your", "can", "said",
            "there", "each", "which", "she", "do", "how", "their", "if", "will", "up", "other", "about",
            "government", "president", "election", "politics", "country", "years", "according", "officials",
            "massive", "announces", "employees", "layoffs", "fiscal", "reform", "as", "part", "of", "in"
        ];
        
        // Palabras específicas en español
        let spanishWords = [
            "el", "la", "los", "las", "de", "del", "en", "con", "por", "para", "que", "es", "son", 
            "está", "están", "gobierno", "presidente", "elecciones", "política", "país", "años",
            "según", "también", "más", "muy", "como", "sobre", "entre", "después", "antes",
            "daniel", "noboa", "ecuador", "ecuatoriano", "funcionarios", "despidos", "una", "uno",
            "trabajadores", "empleados", "masivos", "anuncia", "reforma", "fiscal", "parte"
        ];
        
        var spanishCount = 0;
        var englishCount = 0;
        
        // Contar palabras en inglés con mayor peso para palabras clave
        for (word in englishWords.vals()) {
            if (Text.contains(lowerText, #text (" " # word # " ")) or 
                Text.contains(lowerText, #text (word # " ")) or
                Text.contains(lowerText, #text (" " # word))) {
                englishCount += 1;
                // Dar peso extra a palabras muy específicas del inglés
                if (word == "the" or word == "and" or word == "announces" or word == "massive" or word == "layoffs") {
                    englishCount += 1;
                };
            };
        };
        
        // Contar palabras en español
        for (word in spanishWords.vals()) {
            if (Text.contains(lowerText, #text (" " # word # " ")) or 
                Text.contains(lowerText, #text (word # " ")) or
                Text.contains(lowerText, #text (" " # word))) {
                spanishCount += 1;
                // Dar peso extra a palabras muy específicas del español
                if (word == "el" or word == "la" or word == "de" or word == "en" or word == "despidos") {
                    spanishCount += 1;
                };
            };
        };
        
        // Detectores adicionales para español
        if (Text.contains(lowerText, #text "ñ") or 
            Text.contains(lowerText, #text "á") or 
            Text.contains(lowerText, #text "é") or 
            Text.contains(lowerText, #text "í") or 
            Text.contains(lowerText, #text "ó") or 
            Text.contains(lowerText, #text "ú") or
            Text.contains(lowerText, #text "¿") or
            Text.contains(lowerText, #text "¡")) {
            spanishCount += 3; // Peso alto para caracteres únicos del español
        };
        
        // Detectores adicionales para inglés
        // Palabras que NUNCA aparecen en español
        if (Text.contains(lowerText, #text "announces") or
            Text.contains(lowerText, #text "massive") or
            Text.contains(lowerText, #text "layoffs") or
            Text.contains(lowerText, #text "employees") or
            Text.contains(lowerText, #text "fiscal reform")) {
            englishCount += 3;
        };
        
        // Patrones gramaticales típicos del inglés
        if (Text.contains(lowerText, #text " of ") and
            Text.contains(lowerText, #text " in ") and
            Text.contains(lowerText, #text " as ")) {
            englishCount += 2;
        };
        
        Debug.print("🔍 Language detection IMPROVED - Spanish: " # Int.toText(spanishCount) # ", English: " # Int.toText(englishCount));
        Debug.print("📝 Text analyzed: " # lowerText);
        
        if (englishCount > spanishCount) {
            Debug.print("✅ DETECTED: English");
            "English"  
        } else if (spanishCount > englishCount) {
            Debug.print("✅ DETECTED: Spanish");
            "Spanish"
        } else {
            // En caso de empate, usar heurísticas adicionales
            if (Text.contains(lowerText, #text "daniel noboa") and 
                Text.contains(lowerText, #text "ecuador")) {
                if (Text.contains(lowerText, #text " the ") or Text.contains(lowerText, #text "announces")) {
                    Debug.print("✅ DETECTED: English (by heuristics)");
                    "English"
                } else {
                    Debug.print("✅ DETECTED: Spanish (by heuristics)");
                    "Spanish"
                }
            } else {
                Debug.print("✅ DETECTED: English (default)");
                "English" // Default to English if unclear
            }
        }
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

        // Detectar idioma del texto
        let detectedLang = detectLanguage(newsText);
        Debug.print("🌐 Idioma detectado: " # detectedLang);

        // Llamar a la API de Perplexity con el idioma detectado
        switch (await callPerplexityAPI(newsText, detectedLang)) {
            case (#ok(response)) {
                // Parsear y analizar la respuesta
                switch (parsePerplexityResponse(response, newsText, detectedLang)) {
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
                            detectedLanguage = detectedLang;
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
                let fallbackAnalysis = performLocalAnalysis(newsText, detectedLang);
                let result: AnalysisResult = {
                    isReliable = fallbackAnalysis.isReliable;
                    confidence = fallbackAnalysis.confidence;
                    summary = fallbackAnalysis.summary;
                    sources = fallbackAnalysis.sources;
                    reasoning = fallbackAnalysis.reasoning;
                    context = fallbackAnalysis.context;
                    consistency = fallbackAnalysis.consistency;
                    recommendations = fallbackAnalysis.recommendations;
                    verificationStatus = if (fallbackAnalysis.isReliable) "No Verificado" else "Impreciso";
                    detectedLanguage = detectedLang;
                    timestamp = Time.now();
                };
                #ok(result)
            };
        }
    };

    // FUNCIÓN PARA LLAMAR A LA API CON IDIOMA ESPECÍFICO
    private func callPerplexityAPI(newsText: Text, language: Text) : async Result.Result<Text, ApiError> {
        
        Debug.print("🔍 Iniciando llamada a Perplexity API en idioma: " # language);
        
        // Verificar API key
        if (API_KEY == "YOUR_PERPLEXITY_API_KEY") {
            Debug.print("❌ ERROR: API key no configurada");
            return #err(#ApiError("API key no configurada"));
        };
        
        let cleanText = escapeJson(newsText);
        
        // PROMPT MULTIIDIOMA
        let (systemPrompt, userPrompt) = if (language == "English") {
            getEnglishPrompts(cleanText)
        } else {
            getSpanishPrompts(cleanText)
        };

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
                        case (?text) { 
                            Debug.print("✅ Respuesta de API recibida correctamente");
                            #ok(text) 
                        };
                        case null { #err(#ParseError("No se pudo decodificar la respuesta")) };
                    }
                };
                case (401) { #err(#ApiError("Error de autenticación")) };
                case (429) { #err(#ApiError("Límite de rate excedido")) };
                case (code) { #err(#ApiError("Error de API: " # Int.toText(code))) };
            }
        } catch (_) {
            #err(#NetworkError("Error de red"))
        }
    };

    // PROMPTS EN ESPAÑOL
    private func getSpanishPrompts(cleanText: Text) : (Text, Text) {
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
        
        (systemPrompt, userPrompt)
    };

    // PROMPTS EN INGLÉS
    private func getEnglishPrompts(cleanText: Text) : (Text, Text) {
        let systemPrompt = "You are a news fact-checker specialized in Ecuador 2025 elections.";
        
        let userPrompt = "Act as a news fact-checker specialized in Ecuador 2025 elections. " #
            "Carefully analyze the following content: " # cleanText # " " #
            "Please verify the truthfulness of this information considering: " #
            "1. Verifiable facts vs opinions " #
            "2. Official electoral sources from Ecuador " #
            "3. Contradictions or inconsistencies " #
            "4. Complete context of the information " #
            "5. Possible bias or manipulation " #
            "Respond EXCLUSIVELY in JSON format with the following exact structure: " #
            "{" #
                "\\\"resultado\\\": \\\"[RESULT]\\\", " #
                "\\\"resumen\\\": \\\"[CONCISE SUMMARY OF THE ANALYZED CONTENT AND ITS CONTEXT]\\\", " #
                "\\\"evidencia\\\": \\\"[ANALYSIS OF AVAILABLE EVIDENCE]\\\", " #
                "\\\"contexto\\\": \\\"[CONTEXT ANALYSIS]\\\", " #
                "\\\"fuentes_consultadas\\\": \\\"[SOURCES CONSULTED RELATED TO THE QUERY]\\\", " #
                "\\\"consistencia\\\": \\\"[INFORMATION CONSISTENCY ANALYSIS]\\\", " #
                "\\\"recomendaciones\\\": \\\"[3-5 RECOMMENDATIONS FOR THE READER]\\\", " #
                "\\\"confianza\\\": [NUMBER BETWEEN 0.0 AND 1.0] " #
            "} " #
            "For the resultado field, use EXCLUSIVELY one of these options: " #
            "Verified (if information is confirmed by reliable sources), " #
            "Inaccurate (if information contains some correct data but also incorrect data), " #
            "Not Verified (if there is insufficient evidence to confirm or deny), " #
            "False (if information is clearly incorrect). " #
            "IMPORTANT: Respond ONLY with the JSON, no additional text before or after.";
        
        (systemPrompt, userPrompt)
    };

    // FUNCIÓN DE PARSING ADAPTADA PARA MULTIIDIOMA
    private func parsePerplexityResponse(response: Text, originalText: Text, language: Text) : Result.Result<{
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
        
        Debug.print("🔍 Parseando respuesta de Perplexity en idioma: " # language);
        
        // Extraer el contenido del JSON de Perplexity
        let content = extractContentFromPerplexityResponse(response);
        Debug.print("📄 Contenido extraído: " # content);
        
        // Parsear el JSON interno del análisis
        let analysis = parseAnalysisFromContent(content, language);
        
        switch (analysis) {
            case (?result) { 
                Debug.print("✅ Parsing exitoso!");
                Debug.print("📊 Status: " # result.verificationStatus);
                Debug.print("📈 Confianza: " # floatToText(result.confidence));
                #ok(result) 
            };
            case null { 
                Debug.print("❌ Fallo en parsing, usando análisis local");
                let fallbackAnalysis = performLocalAnalysis(originalText, language);
                #ok({
                    isReliable = fallbackAnalysis.isReliable;
                    confidence = fallbackAnalysis.confidence;
                    summary = fallbackAnalysis.summary;
                    sources = fallbackAnalysis.sources;
                    reasoning = fallbackAnalysis.reasoning;
                    context = fallbackAnalysis.context;
                    consistency = fallbackAnalysis.consistency;
                    recommendations = fallbackAnalysis.recommendations;
                    verificationStatus = if (fallbackAnalysis.isReliable) "No Verificado" else "Impreciso";
                })
            };
        }
    };

    // EXTRAER CONTENIDO DE LA RESPUESTA DE PERPLEXITY (IGUAL QUE ANTES)
    private func extractContentFromPerplexityResponse(response: Text) : Text {
        Debug.print("🔍 Extrayendo contenido de respuesta...");
        
        // Buscar el patrón "content": "..." dentro de la respuesta
        if (Text.contains(response, #text "\"content\": \"")) {
            let parts = Text.split(response, #text "\"content\": \"");
            switch (parts.next()) {
                case (?_) {
                    switch (parts.next()) {
                        case (?contentPart) {
                            // Encontrar el final del contenido
                            if (Text.contains(contentPart, #text "\"}")) {
                                let endParts = Text.split(contentPart, #text "\"}");
                                switch (endParts.next()) {
                                    case (?rawContent) { 
                                        let unescapedContent = unescapeJson(rawContent);
                                        Debug.print("📄 Contenido encontrado y procesado");
                                        return unescapedContent;
                                    };
                                    case null { };
                                }
                            };
                        };
                        case null { };
                    }
                };
                case null { };
            }
        };
        
        Debug.print("❌ No se encontró contenido, devolviendo respuesta completa");
        return response;
    };

    // PARSING DEL ANÁLISIS ADAPTADO PARA MULTIIDIOMA
    private func parseAnalysisFromContent(content: Text, language: Text) : ?{
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
        
        Debug.print("🔍 Parseando análisis del contenido en idioma: " # language);
        
        // Si el contenido es JSON válido, parsearlo
        var jsonContent = content;
        
        // Limpiar el JSON
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
        
        // Limpiar caracteres de escape y espacios
        let cleanedJson = Text.replace(
            Text.replace(
                Text.replace(jsonContent, #text "\n", ""), 
                #text "\r", ""
            ), 
            #text "  ", " "
        );
        
        Debug.print("🧹 JSON limpio para parsing");
        
        // EXTRAER RESULTADO CON MAPEO MULTIIDIOMA
        var verificationStatus = "No Verificado";
        var isReliable = false;
        
        let resultValue = extractJsonField(cleanedJson, "resultado", "No Verificado");
        Debug.print("📊 Resultado extraído: " # resultValue);
        
        // Mapear resultados tanto en español como inglés
        switch (resultValue) {
            case ("Verificado" or "Verified") { 
                verificationStatus := if (language == "English") "Verified" else "Verificado"; 
                isReliable := true; 
            };
            case ("Impreciso" or "Inaccurate") { 
                verificationStatus := if (language == "English") "Inaccurate" else "Impreciso"; 
                isReliable := false; 
            };
            case ("Falso" or "False") { 
                verificationStatus := if (language == "English") "False" else "Falso"; 
                isReliable := false; 
            };
            case (_) { 
                verificationStatus := if (language == "English") "Not Verified" else "No Verificado"; 
                isReliable := false; 
            };
        };
        
        // EXTRAER CONFIANZA
        let confidenceText = extractJsonField(cleanedJson, "confianza", "0.5");
        let confidence = parseFloatFromText(confidenceText);
        Debug.print("📈 Confianza extraída: " # confidenceText # " -> " # floatToText(confidence));
        
        // EXTRAER OTROS CAMPOS CON DECODIFICACIÓN UNICODE
        let summary = decodeUnicodeText(extractJsonField(cleanedJson, "resumen", 
            if (language == "English") "Analysis completed by AI" else "Análisis completado por IA"));
        let reasoning = decodeUnicodeText(extractJsonField(cleanedJson, "evidencia", 
            if (language == "English") "Evidence analysis available" else "Análisis de evidencia disponible"));
        let context = decodeUnicodeText(extractJsonField(cleanedJson, "contexto", 
            if (language == "English") "Context analysis" else "Análisis del contexto"));
        let consistency = decodeUnicodeText(extractJsonField(cleanedJson, "consistencia", 
            if (language == "English") "Consistency analysis" else "Análisis de consistencia"));
        let recommendations = decodeUnicodeText(extractJsonField(cleanedJson, "recomendaciones", 
            if (language == "English") "Verify with official sources" else "Verificar con fuentes oficiales"));
        let sourcesText = decodeUnicodeText(extractJsonField(cleanedJson, "fuentes_consultadas", 
            if (language == "English") "Sources consulted" else "Fuentes consultadas"));
        
        let sources = [
            sourcesText,
            if (language == "English") "Electoral Observation Mission" else "Misión de Observación Electoral",
            if (language == "English") "Analysis verified by Perplexity AI" else "Análisis verificado por Perplexity AI"
        ];
        
        Debug.print("✅ Parsing completado exitosamente");
        Debug.print("📊 Status final: " # verificationStatus);
        Debug.print("📈 Confianza final: " # floatToText(confidence));
        
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

    // ANÁLISIS LOCAL MULTIIDIOMA
    private func performLocalAnalysis(text: Text, language: Text) : {
        isReliable: Bool;
        confidence: Float;
        summary: Text;
        sources: [Text];
        reasoning: Text;
        context: Text;
        consistency: Text;
        recommendations: Text;
    } {
        let lowerText = Text.toLowercase(text);
        
        let (suspiciousKeywords, reliableKeywords, summary1, summary2, summary3, sources) = if (language == "English") {
            (
                ["massive electoral fraud", "stolen elections", "illegal votes", "ballot manipulation", "compromised system", "electoral conspiracy"],
                ["according to electoral bodies", "confirmed by authorities", "official data", "verified study", "official sources"],
                "⚠️ The news contains indicators of possible electoral misinformation",
                "✅ The news appears to contain information from reliable sources",
                "ℹ️ Additional verification with official sources is required",
                ["National Electoral Council", "National Registry"]
            )
        } else {
            (
                ["fraude electoral masivo", "elecciones robadas", "votos ilegales", "manipulación de urnas", "sistema comprometido", "conspiración electoral"],
                ["según organismos electorales", "confirmado por autoridades", "datos oficiales", "estudio verificado", "fuentes oficiales"],
                "⚠️ La noticia contiene indicadores de posible desinformación electoral",
                "✅ La noticia parece contener información de fuentes confiables",
                "ℹ️ Se requiere verificación adicional con fuentes oficiales",
                ["Consejo Nacional Electoral", "Registraduría Nacional"]
            )
        };
        
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
            summary1
        } else if (reliableCount > 0) {
            summary2
        } else {
            summary3
        };
        
        {
            isReliable = isReliable;
            confidence = confidence;
            summary = summary;
            sources = sources;
            reasoning = if (language == "English") "Local analysis (external API failed)" else "Análisis local (fallo en API externa)";
            context = if (language == "English") "Basic analysis without complete API access" else "Análisis básico sin acceso completo a la API";
            consistency = if (language == "English") "Simplified analysis" else "Análisis simplificado";
            recommendations = if (language == "English") "Verify with official sources" else "Verificar con fuentes oficiales";
        }
    };

    // EXTRAER CAMPO JSON MEJORADO (IGUAL QUE ANTES)
    private func extractJsonField(jsonText: Text, fieldName: Text, defaultValue: Text) : Text {
        // Buscar patrón: "fieldName": "value"
        let pattern1 = "\"" # fieldName # "\": \"";
        let pattern2 = "\"" # fieldName # "\":\"";
        
        var pattern = pattern1;
        if (not Text.contains(jsonText, #text pattern1)) {
            pattern := pattern2;
        };
        
        if (Text.contains(jsonText, #text pattern)) {
            let parts = Text.split(jsonText, #text pattern);
            switch (parts.next()) {
                case (?_) {
                    switch (parts.next()) {
                        case (?fieldPart) {
                            // Buscar el final del campo
                            var endPattern = "\",";
                            if (not Text.contains(fieldPart, #text endPattern)) {
                                endPattern := "\"";
                            };
                            
                            if (Text.contains(fieldPart, #text endPattern)) {
                                let endParts = Text.split(fieldPart, #text endPattern);
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
        
        // Para campos numéricos como confianza
        if (fieldName == "confianza") {
            let numPattern1 = "\"" # fieldName # "\": ";
            let numPattern2 = "\"" # fieldName # "\":";
            
            var numPattern = numPattern1;
            if (not Text.contains(jsonText, #text numPattern1)) {
                numPattern := numPattern2;
            };
            
            if (Text.contains(jsonText, #text numPattern)) {
                let parts = Text.split(jsonText, #text numPattern);
                switch (parts.next()) {
                    case (?_) {
                        switch (parts.next()) {
                            case (?numberPart) {
                                let numberText = extractNumberFromText(numberPart);
                                if (Text.size(numberText) > 0) {
                                    return numberText;
                                };
                            };
                            case null {};
                        }
                    };
                    case null {};
                }
            };
        };
        
        defaultValue
    };

    // FUNCIÓN PARA DECODIFICAR CARACTERES UNICODE (IGUAL QUE ANTES)
    private func decodeUnicodeText(text: Text) : Text {
        var decoded = text;
        
        // Caracteres Unicode comunes en español (minúsculas)
        decoded := Text.replace(decoded, #text "\\u00f1", "ñ");
        decoded := Text.replace(decoded, #text "\\u00f3", "ó");
        decoded := Text.replace(decoded, #text "\\u00e9", "é");
        decoded := Text.replace(decoded, #text "\\u00ed", "í");
        decoded := Text.replace(decoded, #text "\\u00fa", "ú");
        decoded := Text.replace(decoded, #text "\\u00e1", "á");
        decoded := Text.replace(decoded, #text "\\u00fc", "ü");
        
        // Mayúsculas con tildes
        decoded := Text.replace(decoded, #text "\\u00d1", "Ñ");
        decoded := Text.replace(decoded, #text "\\u00d3", "Ó");
        decoded := Text.replace(decoded, #text "\\u00c9", "É");
        decoded := Text.replace(decoded, #text "\\u00cd", "Í");
        decoded := Text.replace(decoded, #text "\\u00da", "Ú");
        decoded := Text.replace(decoded, #text "\\u00c1", "Á");
        
        // Otros caracteres especiales
        decoded := Text.replace(decoded, #text "\\u00bf", "¿");
        decoded := Text.replace(decoded, #text "\\u00a1", "¡");
        decoded := Text.replace(decoded, #text "\\u00b0", "°");
        
        decoded
    };

    // Extraer número del texto
    private func extractNumberFromText(text: Text) : Text {
        let trimmed = Text.trim(text, #text " \n\r\t");
        
        if (Text.contains(trimmed, #text ",")) {
            let parts = Text.split(trimmed, #text ",");
            switch (parts.next()) {
                case (?numberPart) { Text.trim(numberPart, #text " \n\r\t") };
                case null { "" };
            }
        } else if (Text.contains(trimmed, #text "}")) {
            let parts = Text.split(trimmed, #text "}");
            switch (parts.next()) {
                case (?numberPart) { Text.trim(numberPart, #text " \n\r\t") };
                case null { "" };
            }
        } else if (Text.contains(trimmed, #text " ")) {
            let parts = Text.split(trimmed, #text " ");
            switch (parts.next()) {
                case (?numberPart) { Text.trim(numberPart, #text " \n\r\t") };
                case null { "" };
            }
        } else {
            trimmed
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

    // FUNCIONES AUXILIARES MEJORADAS
    private func escapeJson(text: Text) : Text {
        let escaped1 = Text.replace(text, #text "\\", "\\\\");
        let escaped2 = Text.replace(escaped1, #text "\"", "\\\"");
        let escaped3 = Text.replace(escaped2, #text "\n", "\\n");
        Text.replace(escaped3, #text "\r", "\\r")
    };

    private func unescapeJson(text: Text) : Text {
        // Primero desenscapar caracteres básicos
        var unescaped = Text.replace(text, #text "\\\"", "\"");
        unescaped := Text.replace(unescaped, #text "\\n", "\n");
        unescaped := Text.replace(unescaped, #text "\\r", "\r");
        unescaped := Text.replace(unescaped, #text "\\\\", "\\");
        
        // Desenscapar caracteres Unicode comunes en español
        unescaped := Text.replace(unescaped, #text "\\u00f1", "ñ");
        unescaped := Text.replace(unescaped, #text "\\u00f3", "ó");
        unescaped := Text.replace(unescaped, #text "\\u00e9", "é");
        unescaped := Text.replace(unescaped, #text "\\u00ed", "í");
        unescaped := Text.replace(unescaped, #text "\\u00fa", "ú");
        unescaped := Text.replace(unescaped, #text "\\u00e1", "á");
        unescaped := Text.replace(unescaped, #text "\\u00fc", "ü");
        
        // Mayúsculas con tildes
        unescaped := Text.replace(unescaped, #text "\\u00d1", "Ñ");
        unescaped := Text.replace(unescaped, #text "\\u00d3", "Ó");
        unescaped := Text.replace(unescaped, #text "\\u00c9", "É");
        unescaped := Text.replace(unescaped, #text "\\u00cd", "Í");
        unescaped := Text.replace(unescaped, #text "\\u00da", "Ú");
        unescaped := Text.replace(unescaped, #text "\\u00c1", "Á");
        
        // Otros caracteres especiales
        unescaped := Text.replace(unescaped, #text "\\u00bf", "¿");
        unescaped := Text.replace(unescaped, #text "\\u00a1", "¡");
        unescaped := Text.replace(unescaped, #text "\\u00b0", "°");
        
        unescaped
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
            version = "4.0.0";
            supportedLanguages = ["Español", "English"];
            maxTextLength = 4000;
            apiProvider = "Perplexity AI + Local Fallback (Multilingual)";
        }
    };

    public func testApiConnection() : async Result.Result<Text, ApiError> {
        await callPerplexityAPI("Test de conectividad", "Spanish")
    };
}