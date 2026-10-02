# Indy YMCA Pool Times

Static site showing lap swim schedules for Indy YMCA branches.

## Local Development

```bash
# Generate schedule data (3 weeks)
ruby scripts/scrape_to_json.rb

# Start local server (no-cache, just refresh browser)
./serve.py

# View at http://localhost:8000
```

## Deployment

Hosted on GitHub Pages. The GitHub Action runs daily at 4am EST to scrape fresh data and deploy to the `gh-pages` branch.

To manually trigger: Actions → "Scrape Pool Schedule" → Run workflow

## URL Parameters

Select specific branches via query param:
```
?branches=fishers,hendricks,westfield
```

Branch keys: `westfield`, `avondale`, `baxter`, `benjamin`, `fishers`, `hendricks`, `irsay`, `jordan`, `orthoindy`, `ransburg`, `witham`

## Notes

**January 2026:** Lane count information (e.g., "10 lanes") is no longer available as structured data. The YMCA switched their schedule system to Y360, which doesn't expose lane availability data.

**Lap pool notes and classes:** Some branches put lane counts in the free-text description of lap swim events (e.g. "4 Lanes", "3 lanes available"), so each lap swim session shows those notes with the time range they apply to. Each session also lists other pool events (water fitness classes, lessons, closures) in the same pool that overlap it, since those take up lanes.
