import { useState } from 'react';
import { project_backend } from 'declarations/project_backend';

function App() {
  const [newsText, setNewsText] = useState('');
  const [analysis, setAnalysis] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (event) => {
    event.preventDefault();
    
    // Validaciones básicas
    if (!newsText.trim()) {
      setError('Por favor, ingresa el texto de la noticia');
      return;
    }

    if (newsText.length > 5000) {
      setError('El texto es demasiado largo (máximo 5000 caracteres)');
      return;
    }

    setLoading(true);
    setError('');
    setAnalysis(null);

    try {
      console.log('Enviando noticia al backend...', newsText);
      const result = await project_backend.analyzeNews(newsText);
      console.log('Resultado completo del backend:', result);
      
      if ('ok' in result) {
        console.log('Análisis exitoso:', result.ok);
        
        let analysisData = result.ok;
        
        console.log('Datos recibidos del backend:');
        console.log('- Full reasoning field:', analysisData.reasoning);
        console.log('- Full summary field:', analysisData.summary);
        console.log('- Full context field:', analysisData.context);
        
        // Si el reasoning contiene JSON (como parece ser el caso)
        if (analysisData.reasoning && analysisData.reasoning.includes('"resultado"')) {
          console.log('Detectado JSON en reasoning, extrayendo...');
          
          try {
            // Buscar el JSON en el reasoning
            let jsonContent = analysisData.reasoning;
            
            // Si está en un mensaje de "Análisis local", extraer la parte JSON
            if (jsonContent.includes('Análisis local (fallo en parsing de API):')) {
              const jsonStart = jsonContent.indexOf('{');
              if (jsonStart !== -1) {
                jsonContent = jsonContent.substring(jsonStart);
              }
            }
            
            // Limpiar el JSON si viene con texto extra
            if (jsonContent.includes('{"id":')) {
              // Es la respuesta completa de Perplexity, extraer solo el content
              const contentMatch = jsonContent.match(/"content":\s*"([^"]+)"/);
              if (contentMatch) {
                jsonContent = contentMatch[1].replace(/\\n/g, '\n').replace(/\\"/g, '"');
              }
            }
            
            // Si el JSON está escapado, des-escaparlo
            if (jsonContent.includes('\\"')) {
              jsonContent = jsonContent.replace(/\\"/g, '"').replace(/\\n/g, '\n');
            }
            
            console.log('JSON a parsear:', jsonContent);
            
            // Intentar parsear el JSON
            const parsedContent = JSON.parse(jsonContent);
            console.log('JSON parseado exitosamente:', parsedContent);
            
            // Actualizar analysisData con el contenido real
            analysisData = {
              ...analysisData,
              summary: parsedContent.resumen || analysisData.summary,
              reasoning: parsedContent.evidencia || analysisData.reasoning,
              context: parsedContent.contexto || analysisData.context,
              consistency: parsedContent.consistencia || analysisData.consistency,
              recommendations: parsedContent.recomendaciones || analysisData.recommendations,
              verificationStatus: parsedContent.resultado || analysisData.verificationStatus,
              confidence: parsedContent.confianza !== undefined ? parsedContent.confianza : analysisData.confidence,
              sources: parsedContent.fuentes_consultadas ? 
                [parsedContent.fuentes_consultadas, "Misión de Observación Electoral", "Análisis verificado por Perplexity AI"] : 
                analysisData.sources
            };
            
            console.log('Datos actualizados después del parsing:');
            console.log('- summary:', analysisData.summary);
            console.log('- reasoning:', analysisData.reasoning);
            console.log('- context:', analysisData.context);
            console.log('- verificationStatus:', analysisData.verificationStatus);
            console.log('- confidence:', analysisData.confidence);
            
          } catch (e) {
            console.error('Error parseando JSON:', e);
            console.log('Usando datos originales del backend');
          }
        }
        
        // Verificar que todos los campos estén presentes
        console.log('Datos finales del análisis:');
        console.log('- verificationStatus:', analysisData.verificationStatus);
        console.log('- confidence:', analysisData.confidence);
        console.log('- summary length:', analysisData.summary ? analysisData.summary.length : 'undefined');
        console.log('- reasoning length:', analysisData.reasoning ? analysisData.reasoning.length : 'undefined');
        console.log('- context length:', analysisData.context ? analysisData.context.length : 'undefined');
        console.log('- consistency length:', analysisData.consistency ? analysisData.consistency.length : 'undefined');
        console.log('- recommendations length:', analysisData.recommendations ? analysisData.recommendations.length : 'undefined');
        console.log('- sources:', analysisData.sources);
        
        setAnalysis(analysisData);
      } else {
        // Manejo de errores del backend
        const errorType = Object.keys(result.err)[0];
        const errorMessage = result.err[errorType];
        setError(`Error: ${errorMessage}`);
        console.error('Error del backend:', result.err);
      }
    } catch (err) {
      console.error('Error calling backend:', err);
      setError('Error de conexión. Verifica que el backend esté funcionando.');
    } finally {
      setLoading(false);
    }
  };

  const clearForm = () => {
    setNewsText('');
    setAnalysis(null);
    setError('');
  };

  const formatDate = (timestamp) => {
    return new Date(Number(timestamp) / 1000000).toLocaleString('es-ES');
  };

  const getStatusConfig = (status) => {
    const configs = {
      "Verificado": {
        color: '#27ae60',
        bgColor: '#d5f4e6',
        icon: '✅',
        description: 'Información confirmada por fuentes confiables'
      },
      "Impreciso": {
        color: '#f39c12',
        bgColor: '#fef9e7',
        icon: '⚠️',
        description: 'Contiene datos correctos pero también incorrectos o engañosos'
      },
      "No Verificado": {
        color: '#3498db',
        bgColor: '#e8f4f8',
        icon: 'ℹ️',
        description: 'No hay suficiente evidencia para confirmar o negar'
      },
      "Falso": {
        color: '#e74c3c',
        bgColor: '#fdf2f2',
        icon: '❌',
        description: 'Información claramente incorrecta'
      }
    };
    return configs[status] || configs["No Verificado"];
  };

  const getConfidenceColor = (confidence) => {
    if (confidence >= 0.8) return '#27ae60';
    if (confidence >= 0.6) return '#f39c12';
    return '#e74c3c';
  };

  const getConfidenceText = (confidence) => {
    if (confidence >= 0.8) return 'Alta';
    if (confidence >= 0.6) return 'Media';
    return 'Baja';
  };

  // Función para extraer enlaces reales del análisis
  const extractLinksFromSources = (sources) => {
    // Mapear fuentes conocidas a sus URLs
    const sourceLinks = {
      "Consejo Nacional Electoral": {
        title: "Consejo Nacional Electoral Ecuador",
        url: "https://www.cne.gob.ec/",
        description: "Sitio oficial del organismo electoral"
      },
      "Consejo Nacional Electoral de Ecuador": {
        title: "Consejo Nacional Electoral Ecuador", 
        url: "https://www.cne.gob.ec/",
        description: "Sitio oficial del organismo electoral"
      },
      "Registraduría Nacional": {
        title: "Registraduría Nacional del Estado Civil",
        url: "https://www.registraduria.gov.co/",
        description: "Organismo de identificación civil"
      },
      "Misión de Observación Electoral": {
        title: "Misión de Observación Electoral",
        url: "https://moe.org.co/",
        description: "Observación independiente de procesos electorales"
      },
      "Participación Ciudadana": {
        title: "Participación Ciudadana Ecuador",
        url: "https://www.participacionciudadana.org/",
        description: "Organización de observación electoral"
      }
    };

    // Si hay fuentes en el análisis, mapearlas
    const links = [];
    
    if (sources && sources.length > 0) {
      sources.forEach(source => {
        // Buscar coincidencias en el mapeo
        let found = false;
        Object.keys(sourceLinks).forEach(key => {
          if (source.includes(key) && !found) {
            links.push(sourceLinks[key]);
            found = true;
          }
        });
        
        // Si no se encuentra, crear enlace genérico
        if (!found && source !== "Análisis verificado por Perplexity AI") {
          links.push({
            title: source,
            url: `https://www.google.com/search?q=${encodeURIComponent(source + " Ecuador elecciones")}`,
            description: "Buscar información oficial"
          });
        }
      });
    }

    // Asegurar que tengamos al menos 3 enlaces
    while (links.length < 3) {
      const defaultLinks = [
        {
          title: "Consejo Nacional Electoral Ecuador",
          url: "https://www.cne.gob.ec/",
          description: "Sitio oficial del organismo electoral"
        },
        {
          title: "Participación Ciudadana Ecuador",
          url: "https://www.participacionciudadana.org/",
          description: "Organización de observación electoral"
        },
        {
          title: "Misión de Observación Electoral",
          url: "https://moe.org.co/",
          description: "Observación independiente de procesos electorales"
        }
      ];
      
      const linkToAdd = defaultLinks[links.length];
      if (linkToAdd && !links.find(l => l.url === linkToAdd.url)) {
        links.push(linkToAdd);
      } else {
        break;
      }
    }

    return links.slice(0, 3); // Máximo 3 enlaces
  };

  return (
    <main className="container">
      <header className="header">
        <img src="/logo2.svg" alt="Logo del verificador" className="logo" />
        <h1>🗳️ Verificador de Noticias Electorales</h1>
        <p className="subtitle">
          Analiza noticias sobre elecciones para detectar posible desinformación
        </p>
      </header>

      <div className="main-content">
        <form onSubmit={handleSubmit} className="news-form">
          <div className="form-group">
            <label htmlFor="newsText">
              Ingresa el texto de la noticia electoral:
            </label>
            <textarea
              id="newsText"
              value={newsText}
              onChange={(e) => setNewsText(e.target.value)}
              placeholder="Pega aquí el texto de la noticia que quieres verificar..."
              rows={6}
              maxLength={5000}
              className="news-input"
            />
            <div className="character-count">
              {newsText.length}/5000 caracteres
            </div>
          </div>

          <div className="form-actions">
            <button 
              type="submit" 
              disabled={loading || !newsText.trim()}
              className="analyze-btn"
            >
              {loading ? '🔍 Analizando...' : '🔍 Analizar Noticia'}
            </button>
            
            <button 
              type="button" 
              onClick={clearForm}
              className="clear-btn"
            >
              🗑️ Limpiar
            </button>
          </div>
        </form>

        {error && (
          <div className="error-message">
            ❌ {error}
          </div>
        )}

        {analysis && (
          <div className="analysis-result">
            <h2>📊 Resultado del Análisis</h2>
            
            {/* DEBUG INFO - TEMPORAL */}
            <div style={{
              background: '#f0f0f0',
              padding: '1rem',
              borderRadius: '8px',
              marginBottom: '1rem',
              fontSize: '0.9rem',
              fontFamily: 'monospace'
            }}>
              <strong>🔧 Debug Info:</strong><br />
              verificationStatus: {analysis.verificationStatus || 'undefined'}<br />
              confidence: {analysis.confidence || 'undefined'}<br />
              summary length: {analysis.summary ? analysis.summary.length : 'undefined'}<br />
              reasoning length: {analysis.reasoning ? analysis.reasoning.length : 'undefined'}<br />
              context length: {analysis.context ? analysis.context.length : 'undefined'}<br />
              consistency length: {analysis.consistency ? analysis.consistency.length : 'undefined'}<br />
              recommendations length: {analysis.recommendations ? analysis.recommendations.length : 'undefined'}
            </div>
            
            {/* Status Principal */}
            <div 
              className="verification-status"
              style={{
                background: getStatusConfig(analysis.verificationStatus || 'No Verificado').bgColor,
                border: `2px solid ${getStatusConfig(analysis.verificationStatus || 'No Verificado').color}`,
                color: getStatusConfig(analysis.verificationStatus || 'No Verificado').color
              }}
            >
              <div className="status-icon">
                {getStatusConfig(analysis.verificationStatus || 'No Verificado').icon}
              </div>
              <h3 className="status-title">
                {(analysis.verificationStatus || 'NO VERIFICADO').toUpperCase()}
              </h3>
              <p className="status-description">
                {getStatusConfig(analysis.verificationStatus || 'No Verificado').description}
              </p>
            </div>

            {/* Confidence Meter */}
            <div className="confidence-section">
              <h4>📈 Nivel de Confianza del Análisis</h4>
              <div className="confidence-meter">
                <div className="confidence-bar">
                  <div 
                    className="confidence-fill"
                    style={{
                      width: `${(analysis.confidence || 0) * 100}%`,
                      background: getConfidenceColor(analysis.confidence || 0)
                    }}
                  ></div>
                </div>
                <span 
                  className="confidence-value"
                  style={{ color: getConfidenceColor(analysis.confidence || 0) }}
                >
                  {getConfidenceText(analysis.confidence || 0)} ({Math.round((analysis.confidence || 0) * 100)}%)
                </span>
              </div>
            </div>

            {/* Analysis Details - MOSTRAR DATOS REALES CON FALLBACKS */}
            <div className="analysis-details">
              
              <div className="analysis-card summary-card">
                <h3>📝 Resumen del Análisis</h3>
                <p>{analysis.summary && analysis.summary.trim() !== "" 
                    ? analysis.summary 
                    : "No se pudo obtener un resumen detallado del análisis"}</p>
              </div>

              <div className="analysis-card reasoning-card">
                <h3>🔍 Evidencia y Razonamiento</h3>
                <p>{analysis.reasoning && analysis.reasoning.trim() !== "" 
                    ? analysis.reasoning 
                    : "No se encontró información específica de evidencia y razonamiento"}</p>
              </div>

              <div className="analysis-card context-card">
                <h3>🌍 Contexto</h3>
                <p>{analysis.context && analysis.context.trim() !== "" 
                    ? analysis.context 
                    : "No se pudo obtener información contextual específica"}</p>
              </div>

              <div className="analysis-card consistency-card">
                <h3>⚖️ Análisis de Consistencia</h3>
                <p>{analysis.consistency && analysis.consistency.trim() !== "" 
                    ? analysis.consistency 
                    : "No se pudo realizar análisis de consistencia detallado"}</p>
              </div>

              <div className="analysis-card recommendations-card">
                <h3>💡 Recomendaciones</h3>
                <div style={{ whiteSpace: 'pre-line' }}>
                  {analysis.recommendations && analysis.recommendations.trim() !== "" 
                    ? analysis.recommendations.split(/\d+\./).filter(item => item.trim()).map((rec, index) => (
                        <div key={index} style={{ marginBottom: '0.5rem' }}>
                          <strong>{index + 1}.</strong> {rec.trim()}
                        </div>
                      ))
                    : (
                      <div>
                        <div style={{ marginBottom: '0.5rem' }}>
                          <strong>1.</strong> Verificar la información con fuentes oficiales
                        </div>
                        <div style={{ marginBottom: '0.5rem' }}>
                          <strong>2.</strong> Consultar múltiples fuentes antes de compartir
                        </div>
                        <div style={{ marginBottom: '0.5rem' }}>
                          <strong>3.</strong> Contrastar con organismos electorales reconocidos
                        </div>
                      </div>
                    )}
                </div>
              </div>

            </div>

            {/* Reference Links - DINÁMICOS */}
            <div className="reference-links">
              <h3>🔗 Enlaces de Referencia para Verificación</h3>
              <div className="links-grid">
                {extractLinksFromSources(analysis.sources).map((link, index) => (
                  <a
                    key={index}
                    href={link.url}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="reference-link"
                  >
                    <div className="link-title">
                      📋 {link.title}
                    </div>
                    <div className="link-description">
                      {link.description}
                    </div>
                    <div className="link-url">
                      {link.url}
                    </div>
                  </a>
                ))}
              </div>
            </div>

            {/* Sources Section - DINÁMICO */}
            <div className="sources-section">
              <h3>📚 Fuentes Consultadas</h3>
              <ul className="sources-list">
                {analysis.sources && analysis.sources.length > 0 ? (
                  analysis.sources.map((source, index) => (
                    <li key={index}>{source}</li>
                  ))
                ) : (
                  <li>No se especificaron fuentes consultadas</li>
                )}
              </ul>
            </div>

            <div className="metadata">
              <small>
                📅 Análisis realizado: {formatDate(analysis.timestamp)}
              </small>
            </div>
          </div>
        )}

        <div className="info-section">
          <h3>ℹ️ Cómo Funciona</h3>
          <ul className="info-list">
            <li>🔍 Analizamos el texto usando inteligencia artificial avanzada</li>
            <li>📊 Clasificamos la información en 4 categorías: Verificado, Impreciso, No Verificado, Falso</li>
            <li>🎯 Proporcionamos un nivel de confianza del análisis</li>
            <li>📋 Sugerimos fuentes oficiales para verificación adicional</li>
          </ul>
          
          <div className="disclaimer">
            <strong>⚠️ Descargo de responsabilidad:</strong>
            <p>
              Este es un análisis automático preliminar con fines educativos. 
              Siempre verifica la información con fuentes oficiales antes de 
              compartir o tomar decisiones basadas en noticias electorales.
            </p>
          </div>
        </div>
      </div>
    </main>
  );
}

export default App;