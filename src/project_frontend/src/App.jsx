import { useState } from 'react';
import { project_backend } from 'declarations/project_backend';

function App() {
  const [newsText, setNewsText] = useState('');
  const [analysis, setAnalysis] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (event) => {
    event.preventDefault();
    
    // Basic validations
    if (!newsText.trim()) {
      setError('Please enter the news text');
      return;
    }

    if (newsText.length > 5000) {
      setError('Text is too long (maximum 5000 characters)');
      return;
    }

    setLoading(true);
    setError('');
    setAnalysis(null);

    try {
      console.log('🔍 Sending news to backend:', newsText);
      const result = await project_backend.analyzeNews(newsText);
      console.log('📊 Complete backend result:', result);
      
      if ('ok' in result) {
        console.log('✅ Successful analysis received');
        
        // Data already parsed from backend
        const backendData = result.ok;
        
        // Create analysis object with received data
        const analysisResult = {
          verificationStatus: backendData.verificationStatus || 'Not Verified',
          confidence: backendData.confidence || 0.5,
          summary: backendData.summary || 'Analysis completed',
          reasoning: backendData.reasoning || 'Evidence analyzed',
          context: backendData.context || 'Context available',
          consistency: backendData.consistency || 'Consistency evaluated',
          recommendations: backendData.recommendations || 'Verify with official sources',
          sources: backendData.sources || ['Sources consulted'],
          timestamp: backendData.timestamp || Date.now() * 1000000,
          isReliable: backendData.isReliable || false,
          detectedLanguage: backendData.detectedLanguage || 'English' // New field
        };
        
        console.log('🎯 Processed data to display:', analysisResult);
        console.log('🌐 Detected language:', analysisResult.detectedLanguage);
        console.log('🔍 Input text language detected:', inputLanguage);
        console.log('📝 First 100 chars:', newsText.substring(0, 100));
        setAnalysis(analysisResult);
        
      } else {
        // Backend error handling
        const errorType = Object.keys(result.err)[0];
        const errorMessage = result.err[errorType];
        setError(`Analysis error: ${errorMessage}`);
        console.error('❌ Backend error:', result.err);
      }
    } catch (err) {
      console.error('💥 Connection error:', err);
      setError('Connection error. Please verify that the backend is running.');
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
    try {
      return new Date(Number(timestamp) / 1000000).toLocaleString('en-US');
    } catch {
      return new Date().toLocaleString('en-US');
    }
  };

  // Enhanced status config with better language handling
  const getStatusConfig = (status) => {
    const configs = {
      // Spanish statuses
      "Verificado": {
        color: '#27ae60',
        bgColor: '#d5f4e6',
        icon: '✅',
        description: 'Information confirmed by reliable sources',
        englishLabel: 'VERIFIED'
      },
      "Impreciso": {
        color: '#f39c12',
        bgColor: '#fef9e7',
        icon: '⚠️',
        description: 'Contains correct data but also incorrect or misleading information',
        englishLabel: 'INACCURATE'
      },
      "No Verificado": {
        color: '#3498db',
        bgColor: '#e8f4f8',
        icon: 'ℹ️',
        description: 'Not enough evidence to confirm or deny',
        englishLabel: 'NOT VERIFIED'
      },
      "Falso": {
        color: '#e74c3c',
        bgColor: '#fdf2f2',
        icon: '❌',
        description: 'Clearly incorrect information',
        englishLabel: 'FALSE'
      },
      // English statuses
      "Verified": {
        color: '#27ae60',
        bgColor: '#d5f4e6',
        icon: '✅',
        description: 'Information confirmed by reliable sources',
        englishLabel: 'VERIFIED'
      },
      "Inaccurate": {
        color: '#f39c12',
        bgColor: '#fef9e7',
        icon: '⚠️',
        description: 'Contains correct data but also incorrect or misleading information',
        englishLabel: 'INACCURATE'
      },
      "Not Verified": {
        color: '#3498db',
        bgColor: '#e8f4f8',
        icon: 'ℹ️',
        description: 'Not enough evidence to confirm or deny',
        englishLabel: 'NOT VERIFIED'
      },
      "False": {
        color: '#e74c3c',
        bgColor: '#fdf2f2',
        icon: '❌',
        description: 'Clearly incorrect information',
        englishLabel: 'FALSE'
      }
    };
    return configs[status] || configs["Not Verified"];
  };

  const getConfidenceColor = (confidence) => {
    if (confidence >= 0.8) return '#27ae60';
    if (confidence >= 0.6) return '#f39c12';
    return '#e74c3c';
  };

  const getConfidenceText = (confidence) => {
    if (confidence >= 0.8) return 'High';
    if (confidence >= 0.6) return 'Medium';
    return 'Low';
  };

  const extractLinksFromSources = (sources) => {
    const defaultLinks = [
      {
        title: "National Electoral Council Ecuador",
        url: "https://www.cne.gob.ec/",
        description: "Official website of the electoral body"
      },
      {
        title: "Citizen Participation Ecuador",
        url: "https://www.participacionciudadana.org/",
        description: "Electoral observation organization"
      },
      {
        title: "Electoral Contentious Court",
        url: "https://www.tce.gob.ec/",
        description: "Electoral jurisdictional body"
      }
    ];

    return defaultLinks;
  };

  const formatRecommendations = (recommendations) => {
    if (!recommendations || typeof recommendations !== 'string') {
      return [
        "Verify information with official sources",
        "Consult multiple sources before sharing",
        "Cross-check with recognized electoral bodies"
      ];
    }

    // Split by numbers (1., 2., etc.)
    if (recommendations.includes('1.')) {
      return recommendations.split(/\d+\./).filter(item => item.trim()).map(rec => rec.trim());
    }

    // Split by line breaks
    if (recommendations.includes('\n')) {
      return recommendations.split('\n').filter(item => item.trim()).map(rec => rec.trim());
    }

    // If it's running text, split by sentences
    const sentences = recommendations.split('.').filter(item => item.trim());
    if (sentences.length > 1) {
      return sentences.map(s => s.trim() + '.');
    }

    return [recommendations];
  };

  // Function to detect if text is primarily in English
  const detectInputLanguage = (text) => {
    const englishWords = ['the', 'and', 'for', 'are', 'with', 'his', 'they', 'this', 'have', 'from', 'government', 'president', 'election'];
    const spanishWords = ['el', 'la', 'los', 'las', 'de', 'del', 'en', 'con', 'por', 'para', 'que', 'es', 'gobierno', 'presidente', 'elecciones'];
    
    const lowerText = text.toLowerCase();
    let englishCount = 0;
    let spanishCount = 0;
    
    englishWords.forEach(word => {
      if (lowerText.includes(word)) englishCount++;
    });
    
    spanishWords.forEach(word => {
      if (lowerText.includes(word)) spanishCount++;
    });
    
    return englishCount > spanishCount ? 'English' : 'Spanish';
  };

  const inputLanguage = detectInputLanguage(newsText);

  return (
    <main className="container">
      <header className="header">
        <img src="/vite.svg" alt="Verifier logo" className="logo" />
        <h1>🗳️ Electoral News Verifier</h1>
        <p className="subtitle">
          Analyze electoral news to detect possible misinformation with decentralized AI
        </p>
      </header>

      <div className="main-content">
        <form onSubmit={handleSubmit} className="news-form">
          <div className="form-group">
            <label htmlFor="newsText">
              Enter the electoral news text (English/Spanish):
            </label>
            <textarea
              id="newsText"
              value={newsText}
              onChange={(e) => setNewsText(e.target.value)}
              placeholder="Paste here the news text you want to verify... Works in English and Spanish!"
              rows={6}
              maxLength={5000}
              className="news-input"
            />
            <div className="character-count">
              {newsText.length}/5000 characters
              {newsText.length > 20 && (
                <span style={{ marginLeft: '10px', fontSize: '0.8rem', color: '#666' }}>
                  Detected: {inputLanguage === 'English' ? '🇺🇸 English' : '🇪🇸 Spanish'}
                </span>
              )}
            </div>
          </div>

          <div className="form-actions">
            <button 
              type="submit" 
              disabled={loading || !newsText.trim()}
              className="analyze-btn"
            >
              {loading ? '🔍 Analyzing with AI...' : '🔍 Analyze News'}
            </button>
            
            <button 
              type="button" 
              onClick={clearForm}
              className="clear-btn"
            >
              🗑️ Clear
            </button>
          </div>
        </form>

        {error && (
          <div className="error-message">
            ❌ {error}
          </div>
        )}

        {loading && (
          <div className="loading-message">
            <div className="loading-spinner"></div>
            <p>🤖 Analyzing news with Perplexity AI...</p>
            <p><small>Processing in {inputLanguage}... This may take a few seconds</small></p>
          </div>
        )}

        {analysis && (
          <div className="analysis-result">
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem' }}>
              <h2>📊 AI Analysis Result</h2>
              <div style={{ fontSize: '0.9rem', color: '#666', fontWeight: '500' }}>
                🌐 Analysis Language: {analysis.detectedLanguage === 'English' ? '🇺🇸 English' : '🇪🇸 Spanish'}
              </div>
            </div>
            
            {/* Main Status */}
            <div 
              className="verification-status"
              style={{
                background: getStatusConfig(analysis.verificationStatus).bgColor,
                border: `2px solid ${getStatusConfig(analysis.verificationStatus).color}`,
                color: getStatusConfig(analysis.verificationStatus).color
              }}
            >
              <div className="status-icon">
                {getStatusConfig(analysis.verificationStatus).icon}
              </div>
              <h3 className="status-title">
                {getStatusConfig(analysis.verificationStatus).englishLabel}
              </h3>
              <p className="status-description">
                {getStatusConfig(analysis.verificationStatus).description}
              </p>
            </div>

            {/* Confidence Meter */}
            <div className="confidence-section">
              <h4>📈 Analysis Confidence Level</h4>
              <div className="confidence-meter">
                <div className="confidence-bar">
                  <div 
                    className="confidence-fill"
                    style={{
                      width: `${analysis.confidence * 100}%`,
                      background: getConfidenceColor(analysis.confidence)
                    }}
                  ></div>
                </div>
                <span 
                  className="confidence-value"
                  style={{ color: getConfidenceColor(analysis.confidence) }}
                >
                  {getConfidenceText(analysis.confidence)} ({Math.round(analysis.confidence * 100)}%)
                </span>
              </div>
            </div>

            {/* Analysis Details - HERE PERPLEXITY DATA IS SHOWN */}
            <div className="analysis-details">
              
              <div className="analysis-card summary-card">
                <h3>📝 Analysis Summary</h3>
                <p>{analysis.summary}</p>
              </div>

              <div className="analysis-card reasoning-card">
                <h3>🔍 Evidence and Reasoning</h3>
                <p>{analysis.reasoning}</p>
              </div>

              <div className="analysis-card context-card">
                <h3>🌍 Context</h3>
                <p>{analysis.context}</p>
              </div>

              <div className="analysis-card consistency-card">
                <h3>⚖️ Consistency Analysis</h3>
                <p>{analysis.consistency}</p>
              </div>

              <div className="analysis-card recommendations-card">
                <h3>💡 Recommendations</h3>
                <div>
                  {formatRecommendations(analysis.recommendations).map((rec, index) => (
                    <div key={index} style={{ marginBottom: '0.75rem', padding: '0.5rem', backgroundColor: '#f8f9fa', borderRadius: '6px' }}>
                      <strong>{index + 1}.</strong> {rec}
                    </div>
                  ))}
                </div>
              </div>

            </div>

            {/* Reference Links */}
            <div className="reference-links">
              <h3>🔗 Reference Links for Verification</h3>
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

            {/* Sources Section */}
            <div className="sources-section">
              <h3>📚 Sources Consulted by AI</h3>
              <ul className="sources-list">
                {analysis.sources && analysis.sources.length > 0 ? (
                  analysis.sources.map((source, index) => (
                    <li key={index}>{source}</li>
                  ))
                ) : (
                  <li>Official sources and electoral databases</li>
                )}
              </ul>
            </div>

            <div className="metadata">
              <small>
                📅 Analysis performed: {formatDate(analysis.timestamp)} | 
                🤖 Powered by Perplexity AI + ICP | 
                🌐 Language: {analysis.detectedLanguage}
              </small>
            </div>
          </div>
        )}

        <div className="info-section">
          <h3>ℹ️ How Veritas Works</h3>
          <ul className="info-list">
            <li>🧠 We analyze text using <strong>Perplexity AI</strong> with access to updated sources</li>
            <li>🌐 <strong>Automatic language detection</strong> - works in English and Spanish</li>
            <li>📊 We classify into 4 categories: <strong>Verified, Inaccurate, Not Verified, False</strong></li>
            <li>🎯 We provide an <strong>analysis confidence level</strong> (0-100%)</li>
            <li>🔗 We suggest <strong>official sources</strong> for additional verification</li>
            <li>⚡ Everything works in a <strong>decentralized</strong> manner on Internet Computer Protocol (ICP)</li>
            <li>🛡️ <strong>Local fallback system</strong> in case of external API failures</li>
          </ul>
          
          <div className="disclaimer">
            <strong>⚠️ Disclaimer:</strong>
            <p>
              This is an automatic analysis with decentralized AI for educational purposes. 
              The system combines advanced Perplexity AI analysis with local verifications.
              Supports both English and Spanish content automatically.
              Always verify information with official sources before 
              sharing or making decisions based on electoral news.
            </p>
          </div>
        </div>
      </div>
    </main>
  );
}

export default App;