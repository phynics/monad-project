import { useState, useEffect, useRef } from 'react'
import './App.css'

interface StatusResponse {
  status: string;
  version: string;
  uptime: number;
  components: Record<string, { status: string; details?: string }>;
}

interface Session {
  id: string;
  title?: string;
  createdAt: string;
  updatedAt: string;
  attachedAgentInstanceId?: string | null;
}

interface Message {
  id: string;
  role: 'user' | 'assistant' | 'system' | 'tool';
  content: string;
  createdAt: string;
}

interface ChatEvent {
  type: string;
  textContent?: string;
  completedMessage?: { message: Message };
  error?: string;
}

function App() {
  const [status, setStatus] = useState<StatusResponse | null>(null);
  const [sessions, setSessions] = useState<Session[]>([]);
  const [currentSessionId, setCurrentSessionId] = useState<string | null>(null);
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState('');
  const [isStreaming, setIsStreaming] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [isInitializing, setIsInitializing] = useState(false);
  
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const API_KEY = 'monad-secret';

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  };

  useEffect(() => {
    scrollToBottom();
  }, [messages]);

  const fetchStatus = async () => {
    try {
      const response = await fetch('/status');
      if (response.ok) setStatus(await response.json());
    } catch (err: any) {
      console.error('Status fetch failed', err);
    }
  };

  const fetchSessions = async () => {
    try {
      const response = await fetch('/api/sessions', {
        headers: { 'Authorization': `Bearer ${API_KEY}` }
      });
      if (response.ok) {
        const data = await response.json();
        setSessions(data.items || []);
      }
    } catch (err: any) {
      setError(`Sessions Fetch Error: ${err.message}`);
    }
  };

  const createSession = async () => {
    try {
      setIsInitializing(true);
      setError(null);
      
      const agentId = await ensureAgentExists();
      if (!agentId) {
        throw new Error('Could not find or create an agent. Please check server configuration.');
      }

      const response = await fetch('/api/sessions', {
        method: 'POST',
        headers: { 
          'Authorization': `Bearer ${API_KEY}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ title: 'New Chat' })
      });
      
      if (response.ok) {
        const newSession = await response.json();
        
        // Attach the agent to the new session
        const attachRes = await fetch(`/api/agents/${agentId}/attach/${newSession.id}`, {
          method: 'POST',
          headers: { 'Authorization': `Bearer ${API_KEY}` }
        });

        if (!attachRes.ok) {
          console.warn('Failed to attach agent to session automatically');
        }

        // Refresh sessions to get the updated list with the new session
        await fetchSessions();
        setCurrentSessionId(newSession.id);
      } else {
        throw new Error('Failed to create session');
      }
    } catch (err: any) {
      setError(err.message);
    } finally {
      setIsInitializing(false);
    }
  };

  const ensureAgentExists = async (): Promise<string | null> => {
    try {
      const agentsRes = await fetch('/api/agents', {
        headers: { 'Authorization': `Bearer ${API_KEY}` }
      });
      
      if (agentsRes.ok) {
        const agents = await agentsRes.json();
        if (agents.length > 0) return agents[0].id;
      }

      const createRes = await fetch('/api/agents', {
        method: 'POST',
        headers: { 
          'Authorization': `Bearer ${API_KEY}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ 
          name: 'Default Assistant', 
          description: 'A helpful AI assistant created by the WebApp.' 
        })
      });

      if (createRes.ok) {
        const newAgent = await createRes.json();
        return newAgent.id;
      }
      
      return null;
    } catch (err) {
      console.error('ensureAgentExists failed', err);
      return null;
    }
  }

  const fetchMessages = async (sessionId: string) => {
    try {
      const response = await fetch(`/api/sessions/${sessionId}/messages`, {
        headers: { 'Authorization': `Bearer ${API_KEY}` }
      });
      if (response.ok) {
        const data = await response.json();
        setMessages(data.items || []);
      }
    } catch (err: any) {
      setError(`Messages Fetch Error: ${err.message}`);
    }
  };

  const sendMessage = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!input.trim() || !currentSessionId || isStreaming) return;

    const session = sessions.find(s => s.id === currentSessionId);
    
    // If no agent attached, try to fix it before sending
    if (!session?.attachedAgentInstanceId) {
        setIsStreaming(true);
        try {
            const agentId = await ensureAgentExists();
            if (agentId) {
                await fetch(`/api/agents/${agentId}/attach/${currentSessionId}`, {
                    method: 'POST',
                    headers: { 'Authorization': `Bearer ${API_KEY}` }
                });
                // Update local session state
                setSessions(prev => prev.map(s => s.id === currentSessionId ? { ...s, attachedAgentInstanceId: agentId } : s));
            }
        } catch (e) {
            console.error('Failed to auto-attach agent', e);
        }
        setIsStreaming(false);
    }

    const userMessage: Message = {
      id: Date.now().toString(),
      role: 'user',
      content: input,
      createdAt: new Date().toISOString()
    };

    setMessages(prev => [...prev, userMessage]);
    setInput('');
    setIsStreaming(true);
    setError(null);

    try {
      const response = await fetch(`/api/sessions/${currentSessionId}/chat/stream`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${API_KEY}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ message: input })
      });

      if (!response.ok) {
          const errData = await response.json();
          if (response.status === 422) {
            throw new Error(errData.message || 'Timeline needs an agent attached.');
          }
          throw new Error(errData.message || 'Failed to send message');
      }

      const reader = response.body?.getReader();
      const decoder = new TextDecoder();
      let assistantMessageContent = '';
      
      const assistantMessageId = 'assistant-' + Date.now();
      setMessages(prev => [...prev, {
          id: assistantMessageId,
          role: 'assistant',
          content: '',
          createdAt: new Date().toISOString()
      }]);

      if (reader) {
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          
          const chunk = decoder.decode(value);
          const lines = chunk.split('\n');
          
          for (const line of lines) {
            if (line.startsWith('data: ')) {
              try {
                const event: ChatEvent = JSON.parse(line.slice(6));
                if (event.textContent) {
                  assistantMessageContent += event.textContent;
                  setMessages(prev => prev.map(m => 
                    m.id === assistantMessageId ? { ...m, content: assistantMessageContent } : m
                  ));
                } else if (event.completedMessage) {
                  setMessages(prev => prev.map(m => 
                    m.id === assistantMessageId ? event.completedMessage!.message : m
                  ));
                } else if (event.error) {
                    setError(event.error);
                }
              } catch (e) {
                console.error('Error parsing SSE', e);
              }
            }
          }
        }
      }
    } catch (err: any) {
      setError(err.message);
    } finally {
      setIsStreaming(false);
      fetchSessions();
    }
  };

  useEffect(() => {
    fetchStatus();
    fetchSessions();
  }, []);

  useEffect(() => {
    if (currentSessionId) {
      fetchMessages(currentSessionId);
    } else {
      setMessages([]);
    }
  }, [currentSessionId]);

  return (
    <div className="app-container">
      <aside className="sidebar">
        <div className="sidebar-header">
          <h2>Monad Chat</h2>
          <button 
            className="new-chat-btn" 
            onClick={createSession}
            disabled={isInitializing}
          >
            {isInitializing ? 'Initialising...' : '+ New Chat'}
          </button>
        </div>
        <nav className="session-list">
          {sessions.map(s => (
            <div 
              key={s.id} 
              className={`session-nav-item ${currentSessionId === s.id ? 'active' : ''}`}
              onClick={() => setCurrentSessionId(s.id)}
            >
              <div className="session-title">{s.title || 'Untitled Session'}</div>
              <div className="session-date">{new Date(s.updatedAt).toLocaleDateString()}</div>
              {!s.attachedAgentInstanceId && <div className="session-warning">No agent attached</div>}
            </div>
          ))}
        </nav>
        <div className="sidebar-footer">
          {status && (
            <div className={`server-status status-${status.status.toLowerCase()}`}>
              Server: {status.status}
            </div>
          )}
        </div>
      </aside>

      <main className="chat-area">
        {error && (
          <div className="error-overlay">
            <div className="error-content">
              <span>{error}</span>
              <button onClick={() => setError(null)}>Close</button>
            </div>
          </div>
        )}

        {!currentSessionId ? (
          <div className="welcome-screen">
            <h1>Welcome to Monad</h1>
            <p>Select a session or create a new one to start chatting.</p>
            <button onClick={createSession} disabled={isInitializing}>
               {isInitializing ? 'Initialising...' : 'Start New Chat'}
            </button>
          </div>
        ) : (
          <>
            <header className="chat-header">
              <h3>{sessions.find(s => s.id === currentSessionId)?.title || 'Chat'}</h3>
            </header>
            
            <div className="message-list">
              {messages.length === 0 && !isStreaming && (
                <div className="empty-chat">
                  Send a message to start the conversation.
                </div>
              )}
              {messages.map(m => (
                <div key={m.id} className={`message-item role-${m.role}`}>
                  <div className="message-bubble">
                    <div className="message-content">{m.content}</div>
                    <div className="message-meta">{new Date(m.createdAt).toLocaleTimeString()}</div>
                  </div>
                </div>
              ))}
              <div ref={messagesEndRef} />
            </div>

            <form className="chat-input-area" onSubmit={sendMessage}>
              <input 
                type="text" 
                value={input}
                onChange={(e) => setInput(e.target.value)}
                placeholder="Type your message..."
                disabled={isStreaming}
              />
              <button type="submit" disabled={isStreaming || !input.trim()}>
                {isStreaming ? '...' : 'Send'}
              </button>
            </form>
          </>
        )}
      </main>
    </div>
  )
}

export default App
