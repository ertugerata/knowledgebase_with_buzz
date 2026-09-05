FROM nousresearch/hermes-agent:latest

# Copy MCP configuration into the image container working directory
COPY mcp_config.json /app/mcp_config.json

# Copy Buzz skills into Hermes bundled skills category directory
COPY skills /opt/hermes/skills/buzz
