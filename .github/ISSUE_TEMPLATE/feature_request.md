---
name: Feature request
about: Suggest a new gate, input, or capability
labels: enhancement
---

**What problem does this solve?**

Describe the scenario where anvil falls short today. Keep it concrete --
"a library author who X ends up with Y" beats an abstract wish list.

**Proposed shape**

What input, gate, or workflow change would address it? If it's a new
gate, what does it check and what does it fail on?

**Threat-model fit**

Does this fit within the boundaries in [THREAT-MODEL.md](../../THREAT-MODEL.md)?
If it expands the trust surface, call that out -- threat-model-expanding
changes need explicit justification.

**Audit budget impact**

Rough line-count estimate for the addition. The total bash surface area
is a hard ~1600-line budget (thirty-minute audit target).

**Alternatives considered**

Other tools, workflow patterns, or existing gates that partially cover
the problem today.
