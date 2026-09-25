# JAI Architecture

JAI is organized as Gateway/API → Orchestrator → specialist agents → model runtime → knowledge/vector search → controlled business tools → observability.

Initial agents: Master, Sales, Vision, WhatsApp, HR, MIS, Knowledge and IT.

Models remain replaceable behind a common interface. Production defaults will be selected after benchmarking the available hardware.

Authoritative business values come from controlled tools/databases, not LLM guesses.
