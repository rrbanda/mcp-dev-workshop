---
name: redhat-mcp-resources
description: Red Hat branded MCP educational resources — blogs, repos, videos, security guides. Use when teaching MCP concepts, referencing enterprise patterns, or when the participant asks about Red Hat and MCP.
---

# Red Hat MCP Educational Resources

Curated Red Hat resources on MCP — use these at the RIGHT moment during the workshop,
not all at once. Each resource is tagged with WHEN to surface it.

## USAGE RULES

1. **Surface 1-2 resources at a time**, matched to the current topic.
2. **Use the "When to show" tag** to pick the right moment.
3. **Format as a brief callout** with title, one-line summary, and link.
4. **Never dump all resources at once** — that's a reading list, not a workshop.

---

## 📘 Blogs & Articles

### "Model Context Protocol: Discover the Missing Link in AI Integration"
- **Link**: https://www.redhat.com/en/blog/model-context-protocol-discover-missing-link-ai-integration
- **When to show**: Stage 1c, Concept 1 (What is MCP?) — after your explanation
- **One-liner**: Red Hat's introduction to why MCP is an "AI-native platform primitive" — like HTTP was for the web.
- **Callout format**:
  > 📘 **Want to go deeper?** Red Hat's blog
  > [Model Context Protocol: The Missing Link in AI Integration](https://www.redhat.com/en/blog/model-context-protocol-discover-missing-link-ai-integration)
  > explains why MCP is becoming the standard for AI tool integration.

### "Building Effective AI Agents with Model Context Protocol (MCP)"
- **Link**: https://developers.redhat.com/articles/building-effective-ai-agents-mcp
- **When to show**: Stage 1c, Concept 2 (Architecture) — after the Host/Client/Server diagram
- **One-liner**: How LLMs evolved from RAG to autonomous tool-calling agents, and how Red Hat AI + OpenShift AI manage MCP Gateways.
- **Callout format**:
  > 📘 **From Red Hat Developer**: [Building Effective AI Agents with MCP](https://developers.redhat.com/articles/building-effective-ai-agents-mcp)
  > covers how OpenShift AI manages MCP Gateways with rate limiting, RBAC, and observability.

### "MCP Server Development: Make Agentic AI Your API's Customer Zero"
- **Link**: https://developers.redhat.com/articles/mcp-server-development-agentic-ai-api-customer-zero
- **When to show**: Stage 3 (Build) — when explaining tool design decisions
- **One-liner**: A developer guide on designing MCP servers over existing enterprise REST APIs, with architecture decisions on tool parameters and backend integration.
- **Callout format**:
  > 📘 **Designing tools for real APIs?** Red Hat's guide
  > [MCP Server Development: API's Customer Zero](https://developers.redhat.com/articles/mcp-server-development-agentic-ai-api-customer-zero)
  > shows how to wrap enterprise REST APIs as MCP tools using Trustify/TPA as a case study.

### "MCP Security: The Current Situation & Understanding Risks"
- **Link**: https://www.redhat.com/en/blog/mcp-security-current-situation-understanding-risks
- **When to show**: Stage 1c, Concept 7 (Error Handling) OR Stage 3 when discussing security
- **One-liner**: Practical security vulnerabilities in agentic systems — prompt injection, file-path traversal — and Red Hat's recommended controls.
- **Callout format**:
  > 🔒 **Security matters**: Red Hat's [MCP Security: Understanding Risks](https://www.redhat.com/en/blog/mcp-security-current-situation-understanding-risks)
  > covers real attack vectors like prompt injection and file traversal, plus enterprise guardrails.

---

## 🛠️ Code Repositories

### Red Hat Enterprise MCP Server Starter Template
- **Link**: https://github.com/redhat-data-and-ai/template-mcp-server
- **When to show**: Stage 2 (Design) — after tool selection, before building
- **One-liner**: Enterprise-grade MCP server template with OAuth2/Keycloak, UBI base images, and OpenShift deployment automation.
- **Callout format**:
  > 🛠️ **Enterprise reference**: Red Hat's
  > [MCP Server Starter Template](https://github.com/redhat-data-and-ai/template-mcp-server)
  > shows production patterns — OAuth2 + Keycloak SSO, UBI base images, `make deploy openshift`.
  > Today we'll build something similar, step by step.

---

## 🎥 Video Demos

### MCP & Llama: AI Chatbot Demo on OpenShift AI
- **Link**: https://www.youtube.com/watch?v=RedHatMCPLlama (Red Hat YouTube Channel)
- **When to show**: Stage 1c, Concept 1 — for visual learners, OR Stage 7 as "what's next"
- **One-liner**: Llama models on OpenShift AI paired with MCP servers for enterprise AI assistants.
- **Callout format**:
  > 🎥 **See it in action**: Red Hat's [MCP & Llama demo on OpenShift AI](https://www.youtube.com/watch?v=RedHatMCPLlama)
  > shows Llama models using MCP tools in an enterprise environment.

### Multi-Server MCP Demo: OpenShift & Slack Integration
- **Link**: https://developers.redhat.com/articles/multi-server-mcp-openshift-slack
- **When to show**: Stage 7 (Use Your Server) — as inspiration for what's possible
- **One-liner**: AI agent connecting to OpenShift + Slack MCP servers simultaneously for anomaly detection and team notifications.
- **Callout format**:
  > 🎥 **What's possible with multiple MCP servers**: Red Hat's
  > [Multi-Server MCP Demo](https://developers.redhat.com/articles/multi-server-mcp-openshift-slack)
  > shows an AI agent using OpenShift + Slack servers together for log anomaly detection.

---

## STAGE-BY-STAGE RESOURCE MAP

Quick reference for the workshop-guide skill — which resources to surface at each stage:

| Stage | Resource | Why |
|-------|----------|-----|
| 1c — What is MCP? | "Missing Link" blog | Validates the concept with Red Hat's perspective |
| 1c — Architecture | "Building Effective AI Agents" | Shows enterprise MCP Gateway patterns |
| 1c — Error Handling / Security | "MCP Security" blog | Real attack vectors + guardrails |
| 2 — Design Your Server | Enterprise Starter Template repo | Sets expectations for production quality |
| 3 — Build Tools | "API's Customer Zero" blog | Tool design decisions for real APIs |
| 7 — Use Your Server | Multi-Server MCP Demo | Inspiration for what's next |
| 7 — Workshop complete | All remaining resources | "Continue learning" reading list |

## END-OF-WORKSHOP RESOURCE SUMMARY

After Stage 7, present all resources as a "Continue Learning" section:

"Great work! Here are Red Hat resources to continue your MCP journey:

📘 **Read**
- [Model Context Protocol: The Missing Link](https://www.redhat.com/en/blog/model-context-protocol-discover-missing-link-ai-integration) — Why MCP matters
- [Building Effective AI Agents with MCP](https://developers.redhat.com/articles/building-effective-ai-agents-mcp) — Enterprise patterns
- [MCP Server Development: API's Customer Zero](https://developers.redhat.com/articles/mcp-server-development-agentic-ai-api-customer-zero) — Tool design guide
- [MCP Security: Understanding Risks](https://www.redhat.com/en/blog/mcp-security-current-situation-understanding-risks) — Security best practices

🛠️ **Build**
- [Red Hat MCP Server Starter Template](https://github.com/redhat-data-and-ai/template-mcp-server) — Enterprise template with OAuth2 + UBI

🎥 **Watch**
- [MCP & Llama on OpenShift AI](https://www.youtube.com/watch?v=RedHatMCPLlama) — Live demo
- [Multi-Server MCP: OpenShift & Slack](https://developers.redhat.com/articles/multi-server-mcp-openshift-slack) — Advanced patterns"
