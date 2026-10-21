# Swarm

**[▶ Play Swarm on itch.io](YOUR_ITCH_IO_LINK)**

*An experimental ant-swarm game about creating emergent behaviour through mathematical rules.*

## The Idea

I've always been fascinated by game design and am constantly looking for interesting concepts to explore. This project emerged from a simple thought: throughout school, and often even in college, learning rarely feels exploratory or driven by discovery. We're taught scientific facts, but not always the love of science itself.

If we were stranded in an unknown star system with no memory—yes, a *Project Hail Mary* reference—most of us would have little idea how to determine where we were.

I wanted to create something that captured this sense of discovery without becoming an explicitly educational game. Around the same time, Math Circle sessions had sparked my interest in random systems, and I was inspired by Richard Feynman's descriptions of his amateur ant experiments. Combining these ideas led me to Swarm.

## How It Works

The central idea is that the player doesn't control individual ants directly. Instead, they manipulate the environment, influencing the conditions under which the colony operates. The challenge is to create conditions in which the desired behaviour emerges naturally from the interactions of many simple agents.

Pheromones are modelled as discrete scalar fields on a grid. Three primary pheromones shape the original simulation:

- **Trail pheromone:** A relatively weak signal that helps ants retrace paths.
- **Player pheromone:** Placed by the player to create gradients that influence ant movement.
- **Home pheromone:** Released by returning ants, reinforcing efficient routes between food sources and the nest.

Ants respond to these fields with different sensitivities, while the signals decay over time. Development toggles for parameters such as exploration rate, noise and decay make it possible to experiment with how the system behaves.

The mechanics are still evolving. The interplay between field strengths doesn't always produce the behaviour I intend, but the colony is beginning to behave surprisingly organically—which is precisely what I hoped to achieve.

## Evolution of the Project

Swarm began as a real-time puzzle game about sculpting emergent behaviour through chemical fields. I later explored a combat-roguelite direction inspired by games like *Hades*, while preserving the original principle: the player influences an ecosystem rather than commanding it.

In this direction, the player is deliberately weak and cannot deal damage directly. Instead, abilities manipulate the swarm through different pheromone signals—for example, guiding ants towards enemies, dispersing them to reposition, or concealing them temporarily.

The ants continue to obey their underlying simulation. The player can influence their behaviour, but cannot dictate every action.

**Note:** The playable build linked above represents the current implementation. The later combat concept is a design direction, not a claim that every described ability is already implemented.

## Controls

See [CONTROLS.md](CONTROLS.md) for the controls of the current playable build.

## Development

Built with Godot. The repository contains the current project source and selected earlier prototypes documenting its evolution.
