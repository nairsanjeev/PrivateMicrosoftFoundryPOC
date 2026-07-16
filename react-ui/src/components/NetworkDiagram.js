import React from 'react';

/*
 Network topology diagram:
 - VNet 1 (Foundry BYO VNet): Agent + AI Search (grounding via private endpoint)
 - VNet 2 (Backend): APIM (public gateway) + Azure Function (private)
 - Agent tool calls go: Agent → APIM public endpoint → Function (private)
*/
export default function NetworkDiagram({ activeNodes, activeEdges }) {
  const isActive = (id) => activeNodes.has(id);
  const edgeActive = (id) => activeEdges.has(id);

  return (
    <div className="network-diagram">
      <h3>🌐 Network Architecture — BYO VNet + APIM Gateway</h3>
      <svg className="network-svg" viewBox="0 0 780 310">

        {/* VNet 1 boundary */}
        <rect className="vnet-boundary" x="8" y="8" width="330" height="294" />
        <text x="15" y="24" fontSize="9.5" fill="#58a6ff" opacity="0.8" fontWeight="600">
          VNet 1 — Foundry BYO (192.168.0.0/16)
        </text>

        {/* Agent Subnet */}
        <rect className="subnet-boundary" x="18" y="32" width="150" height="115" />
        <text className="subnet-label" x="22" y="44">agent-subnet /24</text>
        <text className="subnet-label" x="22" y="53" fontSize="7">Delegated: Microsoft.App</text>

        <g className={`node ${isActive('foundry') ? 'active' : ''}`} transform="translate(26,58)">
          <rect width="134" height="78" rx="6" fill="#1a1f2e" stroke="#58a6ff" strokeWidth="1.5" />
          <text x="67" y="16" textAnchor="middle" fontSize="13">🤖</text>
          <text x="67" y="30" textAnchor="middle" fontSize="10" fill="#58a6ff">Foundry Agent</text>
          <text x="67" y="42" textAnchor="middle" fontSize="8" fill="#8b949e">gpt-4.1 model</text>
          <text x="67" y="55" textAnchor="middle" fontSize="7" fill="#3fb950">✓ AI Search grounding</text>
          <text x="67" y="66" textAnchor="middle" fontSize="7" fill="#bc8cff">✓ OpenAPI tool → APIM</text>
        </g>

        {/* PE Subnet */}
        <rect className="subnet-boundary" x="18" y="155" width="310" height="138" />
        <text className="subnet-label" x="22" y="168">pe-subnet /24 — Private Endpoints</text>

        <g className={`node ${isActive('ai-search') ? 'active' : ''}`} transform="translate(26,176)">
          <rect width="95" height="52" rx="6" fill="#161b22" stroke="#3fb950" strokeWidth="1.2" />
          <text x="47" y="15" textAnchor="middle" fontSize="12">🔍</text>
          <text x="47" y="28" textAnchor="middle" fontSize="9">AI Search</text>
          <text x="47" y="39" textAnchor="middle" fontSize="7" fill="#3fb950">Foundry IQ</text>
          <text x="47" y="48" textAnchor="middle" fontSize="6" fill="#8b949e">Knowledge Base</text>
        </g>

        <g transform="translate(130,176)">
          <rect width="78" height="52" rx="6" fill="#161b22" stroke="#30363d" />
          <text x="39" y="15" textAnchor="middle" fontSize="11">📦</text>
          <text x="39" y="28" textAnchor="middle" fontSize="8">Storage</text>
          <text x="39" y="39" textAnchor="middle" fontSize="7" fill="#8b949e">Files</text>
        </g>

        <g transform="translate(218,176)">
          <rect width="100" height="52" rx="6" fill="#161b22" stroke="#30363d" />
          <text x="50" y="15" textAnchor="middle" fontSize="11">🗃️</text>
          <text x="50" y="28" textAnchor="middle" fontSize="8">Cosmos DB</text>
          <text x="50" y="39" textAnchor="middle" fontSize="7" fill="#8b949e">Threads/State</text>
        </g>

        {/* Grounding edge */}
        <line className={`edge ${edgeActive('foundry-search') ? 'active' : ''}`}
          x1="93" y1="136" x2="73" y2="176" />
        <text x="55" y="160" fontSize="7" fill="#3fb950">grounding</text>

        {/* VNet 2 boundary */}
        <rect className="vnet-boundary" x="430" y="8" width="342" height="294" />
        <text x="438" y="24" fontSize="9.5" fill="#d29922" opacity="0.8" fontWeight="600">
          VNet 2 — Backend API (10.0.0.0/16)
        </text>

        {/* APIM Subnet */}
        <rect className="subnet-boundary" x="442" y="32" width="320" height="122" />
        <text className="subnet-label" x="447" y="44">apim-subnet /24</text>

        <g className={`node ${isActive('apim') ? 'active' : ''}`} transform="translate(460,50)">
          <rect width="284" height="90" rx="8" fill="#1a1f2e" stroke="#d29922" strokeWidth="2" />
          <text x="142" y="17" textAnchor="middle" fontSize="13">🌐</text>
          <text x="142" y="32" textAnchor="middle" fontSize="11" fill="#d29922" fontWeight="bold">Azure API Management</text>
          <text x="142" y="46" textAnchor="middle" fontSize="8" fill="#8b949e">External VNet mode (public IP inbound)</text>
          <text x="142" y="60" textAnchor="middle" fontSize="8" fill="#e6edf3">Single gateway endpoint for all backend APIs</text>
          <text x="142" y="76" textAnchor="middle" fontSize="7.5" fill="#3fb950">
            🌍 Internet reachable → 🔒 Routes to private backend
          </text>
        </g>

        {/* Function Subnet */}
        <rect className="subnet-boundary" x="442" y="162" width="320" height="130" />
        <text className="subnet-label" x="447" y="175">func-subnet /24 (VNet integrated)</text>

        <g className={`node ${isActive('azure-function') ? 'active' : ''}`} transform="translate(460,185)">
          <rect width="284" height="70" rx="6" fill="#1a1f2e" stroke="#f85149" strokeWidth="1.5" />
          <text x="142" y="16" textAnchor="middle" fontSize="13">⚡</text>
          <text x="142" y="30" textAnchor="middle" fontSize="10" fill="#f85149">Azure Function — Order API</text>
          <text x="142" y="44" textAnchor="middle" fontSize="8" fill="#8b949e">publicNetworkAccess: DISABLED</text>
          <text x="142" y="58" textAnchor="middle" fontSize="7.5" fill="#3fb950">
            🔒 Only reachable via APIM (internal VNet routing)
          </text>
        </g>

        {/* APIM → Function edge */}
        <line className={`edge ${edgeActive('apim-function') ? 'active' : ''}`}
          x1="602" y1="140" x2="602" y2="185" />
        <text x="607" y="166" fontSize="7" fill="#d29922">internal</text>

        {/* Agent → APIM edge (tool call) */}
        <path className={`edge ${edgeActive('foundry-apim') ? 'active' : ''}`}
          d="M 160 97 C 280 70, 380 65, 460 95" />
        <text x="290" y="64" fontSize="7.5" fill="#bc8cff">OpenAPI tool call → APIM public endpoint</text>

        {/* User node */}
        <g className={`node ${isActive('user') ? 'active' : ''}`} transform="translate(186,60)">
          <rect width="55" height="30" rx="6" fill="#161b22" stroke="#30363d" />
          <text x="27" y="13" textAnchor="middle" fontSize="11">👤</text>
          <text x="27" y="25" textAnchor="middle" fontSize="8">User</text>
        </g>
        <line className={`edge ${edgeActive('user-foundry') ? 'active' : ''}`}
          x1="186" y1="75" x2="160" y2="85" />

        {/* Legend */}
        <g transform="translate(365, 248)">
          <rect x="-5" y="-8" width="195" height="62" rx="4" fill="#0d1117" stroke="#30363d" opacity="0.9" />
          <text fontSize="8" fill="#8b949e" fontWeight="600">Traffic Flow:</text>
          <text x="0" y="12" fontSize="7" fill="#58a6ff">1. User → Foundry Agent (public)</text>
          <text x="0" y="23" fontSize="7" fill="#3fb950">2. Agent → AI Search (private pe-subnet)</text>
          <text x="0" y="34" fontSize="7" fill="#bc8cff">3. Agent → APIM (public endpoint)</text>
          <text x="0" y="45" fontSize="7" fill="#d29922">4. APIM → Function (internal VNet 2)</text>
        </g>
      </svg>
    </div>
  );
}
