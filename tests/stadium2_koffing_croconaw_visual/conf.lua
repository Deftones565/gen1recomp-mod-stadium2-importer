function love.conf(t)
  t.identity = "pokemon-love2d"
  t.window.title = "Pokemon Stadium 2 model viewer"
  t.window.width = tonumber(os.getenv("STADIUM2_VISUAL_WIDTH")) or 1280
  t.window.height = tonumber(os.getenv("STADIUM2_VISUAL_HEIGHT")) or 720
  t.window.resizable = true
  t.window.vsync = 1
end
