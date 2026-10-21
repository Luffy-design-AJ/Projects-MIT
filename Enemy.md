## Enemies

### Assassin

**Description:** Fast, high-health duelist that prioritises attacking the player over swarm units, running a readable Hades-style rhythm instead of constant pressure.

**Behavior:**
- Targets the player only; ignores the swarm.
- Loops `STALK → WINDUP → STRIKE → BACKOFF → RECOVER`. Aims lock during the wind-up, so the lunge is dodgeable.
- Single-hit lunge (no continuous contact damage), then hops away and recovers while briefly vulnerable.
- In procedural levels, holds its post until the player comes close or it is attacked; re-engages the player after any interruption.
- **Combo hook:** when a Firewall is in the level, it delays its strike until the Firewall is close enough to pin the player (with a fallback timeout, so it can never soft-lock).

**Purpose:** Forces player movement and defensive swarm usage.

### Predator

**Description:** Anti-swarm charger that punishes large concentrations of swarm units.

**Behavior:**
- Searches for dense swarm clusters within its scan radius.
- Enters a charge state when a cluster is detected, then charges through it.
- Damages swarm units it passes through, with a chance of a heavy kill hit.
- Brief grace period after waking, then hunts continuously.
- **Combo hook:** charges the lure spot of a nearby awake Siren even before the swarm has fully clumped there — the clump-and-pounce pair fires on its own.

**Purpose:** Encourages alternating between gathering and scattering the swarm.

### Firewall

**Description:** Slow, heavy enemy surrounded by a pheromone distortion field.

**Behavior:**
- Very slow movement, high health (the tankiest crowd-control unit).
- Inside its field, the swarm's pheromone reading is scrambled with zero-mean noise, and the field's rim gives a soft outward nudge.
- Swarm response becomes unreliable within the field — ants can still be drawn in, but cannot hold formation.
- Field effects do not stack; only the strongest Firewall influences a given point.

**Purpose:** Creates areas where swarm control is difficult.

### Broodmother

**Description:** Very slow, very tanky "heavy hijacker" that turns your own swarm's instincts against your economy rather than killing units.

**Behavior:**
- Crawls toward the player while continuously painting home pheromone around itself.
- Carrying foragers treat it as a nest, climb to it, and deposit their food — which it skims, healing itself in the process.
- Never kills ants directly; it starves deliveries instead.
- While food is disabled in this build, it siphons health from ants gathered around it as an alternate payoff.
- **Immune to swarm damage** — only the player's melee can finish it (otherwise the very ants it attracts would destroy it).

**Purpose:** Attacks your resource economy and punishes parking the swarm on a fake nest.

### Siren

**Description:** Heavy bait that mimics your ATTRACT to gather the swarm, then devours it.

**Behavior:**
- Continuously emits a lure field that the swarm reads as an attract, drawing ants in.
- Once enough units are caught inside the lure, it telegraphs a wind-up.
- Snaps shut, dealing lethal damage to everything caught in the lure radius.
- Then recovers, giving the player a window to scatter the swarm or strike back.
- **Immune to swarm damage**, like the Broodmother.
- **Combo hook:** an awake Predator nearby will charge the Siren's bait spot.

**Purpose:** Punishes leaving the swarm clumped and forces you to read telegraphs.
