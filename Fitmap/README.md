# Fitmap Exploration Routing Prototype

This prototype demonstrates route planning for journeys where the experience matters as much as the destination. It uses:

- Leaflet and OpenStreetMap tiles on the frontend.
- A local Node backend with A* route search.
- User-adjustable weights for elevation, traffic, and nature.
- Destination or loop routing.
- Required stops entered as coordinates or added by clicking the map.

## Run

```bash
npm start
```

Then open `http://localhost:5173`.

## Notes

The backend currently uses a generated street-like graph around San Francisco with synthetic elevation, traffic, and nature scores. This keeps the product prototype dependency-free and easy to run. In a production version, the same A* weighting model can be connected to open-source map data from OpenStreetMap via tools such as OSRM, Valhalla, GraphHopper, or a custom OSM/PBF import pipeline.
