import React from 'react';

export default function ConfigPanel({ config, onChange, onReset, threadId }) {
  const update = (key, value) => onChange({ ...config, [key]: value });

  return (
    <div className="config-panel">
      <div className="config-field" style={{ flex: 2 }}>
        <label>Project Endpoint</label>
        <input
          type="text"
          placeholder="https://<account>.services.ai.azure.com/api/projects/<project>"
          value={config.projectEndpoint}
          onChange={e => update('projectEndpoint', e.target.value)}
        />
      </div>
      <div className="config-field">
        <label>Agent ID</label>
        <input
          type="text"
          placeholder="asst_xxxxxxxx"
          value={config.agentId}
          onChange={e => update('agentId', e.target.value)}
        />
      </div>
      <div className="config-actions">
        <button onClick={onReset}>New Thread</button>
        {threadId && <span className="thread-id">Thread: {threadId.slice(0, 12)}…</span>}
      </div>
    </div>
  );
}
