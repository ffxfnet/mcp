#!/bin/sh
# Adds the FFxF MCP server to Claude Code. Set FFXF_API_KEY first.
claude mcp add --transport http ffxf https://ffxf.net/mcp \
  --header "Authorization: Bearer ${FFXF_API_KEY}"
