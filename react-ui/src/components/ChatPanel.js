import React, { useRef, useEffect, useState } from 'react';

export default function ChatPanel({ messages, onSend, sending }) {
  const [input, setInput] = useState('');
  const bottomRef = useRef(null);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  const handleSubmit = (e) => {
    e.preventDefault();
    const text = input.trim();
    if (!text || sending) return;
    setInput('');
    onSend(text);
  };

  const suggestions = [
    "What laptops do you have in stock?",
    "Check stock for PHONE-001",
    "What's your return policy?",
    "Place an order for 2 ThinkPad X1 Carbons",
    "What warranty options are available?",
  ];

  return (
    <div className="chat-panel">
      <h3>💬 Agent Chat</h3>
      <div className="chat-messages">
        {messages.length === 0 && (
          <div style={{ textAlign: 'center', padding: '40px 20px' }}>
            <p style={{ color: 'var(--text-muted)', marginBottom: '16px' }}>
              Send a message to test the Foundry agent. Try these:
            </p>
            {suggestions.map((s, i) => (
              <button
                key={i}
                onClick={() => onSend(s)}
                style={{
                  display: 'block',
                  width: '100%',
                  textAlign: 'left',
                  padding: '10px 14px',
                  margin: '6px 0',
                  background: 'var(--bg)',
                  border: '1px solid var(--border)',
                  borderRadius: '8px',
                  color: 'var(--accent)',
                  cursor: 'pointer',
                  fontSize: '0.85rem',
                }}
              >
                {s}
              </button>
            ))}
          </div>
        )}
        {messages.map((msg, i) => (
          <div key={i} className={`chat-msg ${msg.role}`}>
            {msg.content}
            {msg.toolCalls?.length > 0 && (
              <div style={{ marginTop: '6px' }}>
                {msg.toolCalls.map((tc, j) => (
                  <span key={j} className="tool-badge">
                    🔧 {tc.type}: {tc.name || 'tool'}
                  </span>
                ))}
              </div>
            )}
          </div>
        ))}
        {sending && (
          <div className="chat-msg assistant" style={{ opacity: 0.6 }}>
            <span style={{ animation: 'pulse 1s infinite' }}>Thinking...</span>
          </div>
        )}
        <div ref={bottomRef} />
      </div>
      <form className="chat-input-bar" onSubmit={handleSubmit}>
        <input
          type="text"
          placeholder="Ask about products, inventory, or policies..."
          value={input}
          onChange={e => setInput(e.target.value)}
          disabled={sending}
        />
        <button type="submit" disabled={sending || !input.trim()}>
          Send
        </button>
      </form>
    </div>
  );
}
