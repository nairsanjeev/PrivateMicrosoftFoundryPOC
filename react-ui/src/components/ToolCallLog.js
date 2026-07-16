import React, { useRef, useEffect } from 'react';

export default function ToolCallLog({ toolCalls }) {
  const bottomRef = useRef(null);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [toolCalls]);

  return (
    <div className="tool-call-log">
      <h3>🔧 Tool Call Trace</h3>
      {toolCalls.length === 0 ? (
        <p className="tool-call-empty">
          Tool calls will appear here as the agent processes requests.
          Watch the network diagram light up as traffic flows through the private VNet.
        </p>
      ) : (
        toolCalls.map((tc, i) => (
          <div key={i} className="tool-call-entry">
            <div className="tc-header">
              <span className="tc-type">{tc.type}</span>
              <span className="tc-time">
                {new Date(tc.timestamp).toLocaleTimeString()}
              </span>
            </div>
            <div className="tc-name">
              {tc.name || tc.function_name || 'tool_call'}
            </div>
            {tc.arguments && (
              <pre style={{ fontSize: '0.7rem', color: 'var(--text-muted)', marginTop: '4px' }}>
                {typeof tc.arguments === 'string'
                  ? tc.arguments
                  : JSON.stringify(tc.arguments, null, 2)}
              </pre>
            )}
            <div className="tc-network">
              {tc.type === 'azure_ai_search'
                ? '🔒 VNet 1 → pe-subnet → AI Search (private endpoint)'
                : '🌐 Agent → APIM (public) → 🔒 Function (VNet 2, private)'}
            </div>
          </div>
        ))
      )}
      <div ref={bottomRef} />
    </div>
  );
}
