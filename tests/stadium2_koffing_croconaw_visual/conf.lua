function love.conf(t)
  t.identity = "pokemon-love2d"
  -- Match the packaged game's save root so this standalone visual harness
  -- reads the same playthrough-scoped mod_storage cache.  A source `love .`
  -- run normally appends a `love/` directory, which silently points the test
  -- at a different (usually empty or incomplete) cache.
  t.appendidentity = os.getenv("STADIUM2_VISUAL_APPEND_IDENTITY") == "1"
  t.window.title = "Pokemon Stadium 2 model viewer"
  t.window.width = tonumber(os.getenv("STADIUM2_VISUAL_WIDTH")) or 1280
  t.window.height = tonumber(os.getenv("STADIUM2_VISUAL_HEIGHT")) or 720
  t.window.resizable = true
  t.window.vsync = 1
end
