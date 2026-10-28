# Fitmap

**Run locally:** `npm start` → `http://localhost:5173`

*A route planner where the journey matters as much as the destination.*

## The Idea

Most route planners answer one question: what is the fastest way from A to B? That is the wrong question for a run, a ride or a walk you are taking for its own sake.

Fitmap flips it around. You say how far you want to go and what the route should feel like — greener, flatter, quieter — and it finds a path that fits.

## How It Works

Routes come from A* search over a street graph, where the cost of each edge is:

**cost = distance + elevation gain + traffic penalty − nature reward**

Three sliders weight those terms, so the same start and the same distance can produce a flat riverside loop or a short, steep route through back streets.

A round trip has no destination node to search for, so the backend generates a set of candidate loops around the start — different radii and bearings — routes each one, and keeps whichever lands closest to the requested distance. Point-to-point routes work the same way: if the direct path is shorter than the target, scenic detours are inserted to either side of the line and scored against the same weights. Required stops are routed in order, so a route can be built around a viewpoint or a water fountain.

Every result reports distance, elevation gain, traffic level, nature score, estimated travel time and the time lost to traffic.

The prototype runs on a synthetic street grid around San Francisco with generated elevation, traffic and nature values, which keeps it dependency-free and quick to run. The same weighting model is built to sit on top of real OpenStreetMap data through tools such as OSRM, Valhalla or GraphHopper.
