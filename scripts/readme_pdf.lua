-- Pandoc filter for README.pdf: GitHub-style HTML images become real figures.
-- <img src="assets/x.svg" alt="..."> -> an image of assets/x.pdf (converted with rsvg-convert);
-- other raw HTML (<p align=...>) is dropped; remote images (badges) are dropped;
-- relative links are rewritten (see Link).

local function svg_to_pdf(src)
  local pdf = src:gsub("%.svg$", ".pdf")
  local ok = os.execute(string.format("rsvg-convert -f pdf -o %q %q", pdf, src))
  if not ok then error("rsvg-convert failed for " .. src) end
  return pdf
end

local function local_image(src, alt)
  if src:match("^https?://") then return nil end
  if src:match("%.svg$") then src = svg_to_pdf(src) end
  return pandoc.Image({pandoc.Str(alt or "")}, src)
end

function RawInline(el)
  if el.format ~= "html" then return nil end
  local src = el.text:match('<img[^>]-src="([^"]+)"')
  if not src then return {} end
  local alt = el.text:match('alt="([^"]*)"')
  return local_image(src, alt) or {}
end

function RawBlock(el)
  if el.format ~= "html" then return nil end
  local imgs = {}
  for tag in el.text:gmatch("<img[^>]*>") do
    local src = tag:match('src="([^"]+)"')
    local img = src and local_image(src, tag:match('alt="([^"]*)"'))
    if img then table.insert(imgs, img) end
  end
  if #imgs == 0 then return {} end
  return pandoc.Para(imgs)
end

-- The source repository is private: a relative link would lead nowhere for a reader.
-- The security features are published in macula-codex; any other relative link becomes text.
function Link(el)
  if el.target:match("^https?://") or el.target:match("^mailto:") then return nil end
  if el.target:match("^SECURITY_FEATURES") then
    el.target = "https://github.com/macula-io/macula-codex/releases"
    return el
  end
  return el.content
end

function Image(el)
  if el.src:match("^https?://") then return {} end
  if el.src:match("%.svg$") then el.src = svg_to_pdf(el.src) end
  return el
end
