import React, { useState, useCallback } from 'react';
import ChatPanel from './components/ChatPanel';
import NetworkDiagram from './components/NetworkDiagram';
import ToolCallLog from './components/ToolCallLog';
import ConfigPanel from './components/ConfigPanel';
import './App.css';

export default function App() {
  const [config, setConfig] = useState({
    projectEndpoint: '',
    agentId: '',
  });
  const [messages, setMessages] = useState([]);
  const [toolCalls, setToolCalls] = useState([]);
  const [activeNodes, setActiveNodes] = useState(new Set());
  const [activeEdges, setActiveEdges] = useState(new Set());
  const [threadId, setThreadId] = useState(null);
  const [sending, setSending] = useState(false);

  const animateFlow = useCallback((nodes, edges, durationMs = 1200) => {
    setActiveNodes(new Set(nodes));
    setActiveEdges(new Set(edges));
    setTimeout(() => {
      setActiveNodes(new Set());
      setActiveEdges(new Set());
    }, durationMs);
  }, []);

  const handleSend = useCallback(async (text) => {
    if (!config.projectEndpoint || !config.agentId) {
      setMessages(prev => [...prev, {
        role: 'system',
        content: 'Please configure the Project Endpoint and Agent ID first.',
      }]);
      return;
    }

    const userMsg = { role: 'user', content: text, timestamp: new Date().toISOString() };
    setMessages(prev => [...prev, userMsg]);
    setSending(true);

    // Animate: User → Internet → Foundry endpoint
    animateFlow(['user', 'internet', 'foundry'], ['user-internet', 'internet-foundry']);

    try {
      const res = await fetch('/api/chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          projectEndpoint: config.projectEndpoint,
          agentId: config.agentId,
          threadId,
          message: text,
        }),
      });

      const data = await res.json();
      if (!res.ok) throw new Error(data.error || 'Request failed');

      setThreadId(data.threadId);

      // Process tool calls and animate accordingly
      if (data.toolCalls?.length) {
        for (const tc of data.toolCalls) {
          const newTc = {
            ...tc,
            timestamp: new Date().toISOString(),
          };
          setToolCalls(prev => [...prev, newTc]);

          if (tc.type === 'azure_ai_search') {
            // Grounding: Agent → AI Search via private endpoint
            animateFlow(
              ['foundry', 'ai-search'],
              ['foundry-search'],
              1500
            );
          } else if (tc.type === 'function' || tc.type === 'openapi') {
            // Tool call: Agent → APIM (public) → Function (private)
            animateFlow(
              ['foundry', 'apim', 'azure-function'],
              ['foundry-apim', 'apim-function'],
              1800
            );
          }
        }
      }

      const assistantMsg = {
        role: 'assistant',
        content: data.response,
        timestamp: new Date().toISOString(),
        toolCalls: data.toolCalls,
      };
      setMessages(prev => [...prev, assistantMsg]);

      // Animate response back
      animateFlow(['foundry', 'internet', 'user'], ['foundry-internet', 'internet-user']);
    } catch (err) {
      setMessages(prev => [...prev, {
        role: 'system',
        content: `Error: ${err.message}`,
        timestamp: new Date().toISOString(),
      }]);
    } finally {
      setSending(false);
    }
  }, [config, threadId, animateFlow]);

  const handleReset = () => {
    setMessages([]);
    setToolCalls([]);
    setThreadId(null);
  };

  return (
    <div className="app">
      <header className="app-header">
        <h1>🔒 Microsoft Foundry — BYO VNet Agent Tester</h1>
        <p className="subtitle">
          Testing network-isolated agents with AI Search grounding + Azure Function tools
        </p>
      </header>

      <ConfigPanel config={config} onChange={setConfig} onReset={handleReset} threadId={threadId} />

      <div className="main-content">
        <div className="left-panel">
          <NetworkDiagram activeNodes={activeNodes} activeEdges={activeEdges} />
          <ToolCallLog toolCalls={toolCalls} />
        </div>
        <div className="right-panel">
          <ChatPanel
            messages={messages}
            onSend={handleSend}
            sending={sending}
          />
        </div>
      </div>
    </div>
  );
}
