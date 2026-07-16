"""
Backend API server for the React UI.
Proxies chat requests to the Foundry Agent Service.

Run: pip install flask azure-ai-projects azure-identity
Then: python server.py
"""
import os
import json
from flask import Flask, request, jsonify, send_from_directory
from azure.identity import DefaultAzureCredential
from azure.ai.projects import AIProjectClient

app = Flask(__name__, static_folder='react-ui/build', static_url_path='')

credential = DefaultAzureCredential()
clients = {}


def get_client(endpoint):
    if endpoint not in clients:
        clients[endpoint] = AIProjectClient(endpoint=endpoint, credential=credential)
    return clients[endpoint]


@app.route('/api/chat', methods=['POST'])
def chat():
    data = request.get_json()
    project_endpoint = data.get('projectEndpoint')
    agent_id = data.get('agentId')
    thread_id = data.get('threadId')
    message = data.get('message')

    if not all([project_endpoint, agent_id, message]):
        return jsonify({'error': 'Missing required fields: projectEndpoint, agentId, message'}), 400

    try:
        client = get_client(project_endpoint)

        # Create or reuse thread
        if not thread_id:
            thread = client.agents.create_thread()
            thread_id = thread.id

        # Send message
        client.agents.create_message(
            thread_id=thread_id,
            role='user',
            content=message,
        )

        # Run the agent
        run = client.agents.create_and_process_run(
            thread_id=thread_id,
            agent_id=agent_id,
        )

        # Extract tool calls from run steps
        tool_calls = []
        try:
            steps = client.agents.list_run_steps(thread_id=thread_id, run_id=run.id)
            for step in steps.data:
                if step.type == 'tool_calls' and hasattr(step, 'step_details'):
                    for tc in step.step_details.tool_calls:
                        tc_info = {
                            'type': tc.type,
                            'name': getattr(tc, 'function', {}).get('name', '') if hasattr(tc, 'function') else tc.type,
                        }
                        if hasattr(tc, 'function') and hasattr(tc.function, 'arguments'):
                            tc_info['arguments'] = tc.function.arguments
                        if hasattr(tc, 'azure_ai_search'):
                            tc_info['type'] = 'azure_ai_search'
                            tc_info['name'] = 'AI Search Query'
                        tool_calls.append(tc_info)
        except Exception:
            pass  # Tool call extraction is best-effort

        # Get response messages
        messages = client.agents.list_messages(thread_id=thread_id)
        response_text = ''
        for msg in messages.data:
            if msg.role == 'assistant' and msg.run_id == run.id:
                for content in msg.content:
                    if hasattr(content, 'text'):
                        response_text += content.text.value
                break

        return jsonify({
            'threadId': thread_id,
            'runId': run.id,
            'status': run.status,
            'response': response_text,
            'toolCalls': tool_calls,
        })

    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/health', methods=['GET'])
def health():
    return jsonify({'status': 'healthy', 'service': 'foundry-byo-vnet-tester'})


# Serve React app
@app.route('/')
def serve_react():
    return send_from_directory(app.static_folder, 'index.html')


@app.errorhandler(404)
def not_found(e):
    return send_from_directory(app.static_folder, 'index.html')


if __name__ == '__main__':
    port = int(os.environ.get('PORT', 3001))
    print(f"🚀 Server running on http://localhost:{port}")
    print(f"   React UI: http://localhost:{port}")
    print(f"   API: http://localhost:{port}/api/chat")
    app.run(host='0.0.0.0', port=port, debug=True)
