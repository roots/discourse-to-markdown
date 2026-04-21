# Discourse to Markdown

A Discourse plugin that returns forum content in Markdown when the client sends `Accept: text/markdown` or appends `.md` to any content URL. HTML responses advertise the Markdown sibling via a `Link` header and `<link rel="alternate">` tag so crawlers and agents can discover it without sending `Accept`.

> [!TIP]
> Learn more about serving Markdown to agents and check your site's AI-readiness at [acceptmarkdown.com](https://acceptmarkdown.com/).

## Installation

Add the plugin to your `app.yml`:

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - git clone https://github.com/roots/discourse-to-markdown.git
```

Then rebuild:

```bash
cd /var/discourse
./launcher rebuild app
```

## Usage

### Accept header (ideal for LLMs and content agents)

Send `Accept: text/markdown` to any content URL. The plugin overrides Rails' built-in negotiation with a spec-correct RFC 9110 §12.5.1 parser so specificity wins over the wildcard tie that would otherwise favour HTML.

```bash
# Single topic
curl -H "Accept: text/markdown" https://example.com/t/welcome/5

# Single post within a topic
curl -H "Accept: text/markdown" https://example.com/t/welcome/5/3

# Topic lists
curl -H "Accept: text/markdown" https://example.com/latest
curl -H "Accept: text/markdown" https://example.com/top
curl -H "Accept: text/markdown" https://example.com/c/general/4
curl -H "Accept: text/markdown" https://example.com/tag/announcements
```

### `.md` URL suffix (shareable)

Appending `.md` to any supported route returns the same Markdown representation and is a first-class, shareable URL:

```bash
curl https://example.com/t/welcome/5.md
curl https://example.com/latest.md
curl https://example.com/c/general/4.md
curl https://example.com/tag/announcements.md
```

`.md` responses carry `X-Robots-Tag: noindex, nofollow` so search engines don't index the Markdown alias alongside the canonical HTML page. Toggle with the `discourse_to_markdown_md_urls_enabled` site setting.

### Discovery

Every HTML response on a supported route advertises the Markdown sibling two ways:

```
Link: </t/welcome/5.md>; rel="alternate"; type="text/markdown"
```

```html
<link rel="alternate" type="text/markdown" href="/t/welcome/5.md">
```

RSS feeds (`/latest.rss`, `/top.rss`, etc.) also carry an `<atom:link>` pointing at the Markdown equivalent so feed readers and LLMs can discover it:

```xml
<atom:link href="/latest.md" rel="alternate" type="text/markdown" />
```

### Supported routes

| Route | HTML | Markdown |
| --- | --- | --- |
| Topic | `/t/:slug/:id` | `/t/:slug/:id.md` |
| Single post | `/t/:slug/:id/:post_number` | `/t/:slug/:id/:post_number.md` |
| Category | `/c/:slug/:id` | `/c/:slug/:id.md` |
| Tag | `/tag/:tag` | `/tag/:tag.md` |
| Latest | `/latest` | `/latest.md` |
| Top | `/top` | `/top.md` |
| Hot | `/hot` | `/hot.md` |
| User activity | `/u/:username/activity` | `/u/:username/activity.md` |

### Response headers

Markdown responses carry:

- `Content-Type: text/markdown; charset=utf-8`
- `Vary: Accept` — tells caches to key by `Accept` so HTML and Markdown representations don't cross-serve
- `X-Robots-Tag: noindex, nofollow` (on `.md` URL responses only)

## Site settings

All settings live under Admin → Settings → Plugins.

| Setting | Default | Purpose |
| --- | --- | --- |
| `discourse_to_markdown_enabled` | `false` | Master switch for the plugin |
| `discourse_to_markdown_md_urls_enabled` | `true` | Accept `.md` URL suffixes as a sibling to the HTML route |
| `discourse_to_markdown_strict_accept` | `false` | Return `406 Not Acceptable` when the client's `Accept` header excludes both `text/html` and `text/markdown` |
| `discourse_to_markdown_emit_vary` | `true` | Reserved; Discourse already emits `Vary: Accept` on every front-end response |
| `discourse_to_markdown_include_post_metadata` | `true` | Include URL, category, tags, author, timestamps in the Markdown representation |

## Conversion notes

The plugin converts Discourse's `cooked` HTML (the rendered representation readers see, with oneboxes expanded, mentions linked, and quotes attributed) to Markdown — not `raw` (Discourse's authoring syntax, which leaks `[quote=…]` and `:shortcode:` markers). This preserves what readers actually see and keeps the output portable across any GFM-compatible Markdown renderer.

Discourse-specific cooked constructs are rewritten before conversion:

- `<aside class="quote">` → blockquote with `> [@user](post-url):` attribution
- `<aside class="onebox">` → blockquote with title, URL, and excerpt
- `<details><summary>` → blockquote with bolded summary + body
- `<a class="mention">@user</a>` → `@user` literal
- `<a class="hashtag">#tag</a>` → `#tag` literal
- `<img class="emoji" title=":smile:">` → `:smile:` shortcode
- `<div class="lightbox-wrapper">` → image with the full-size URL
- `<div class="poll">` → `_Poll: {title} (view on site)_` stub

## Performance

Converted Markdown is cached per post in `Discourse.cache` (Redis in production, memory in dev/test) keyed on `post.id` + `post.updated_at`. Edits produce a fresh key automatically — no explicit invalidation hook needed. Cache entries expire after 1 week.

## Resources

- [acceptmarkdown.com](https://acceptmarkdown.com/) — serving Markdown to agents via content negotiation, plus a readiness check for your site
- [RFC 9110 §12.5.1 — Proactive Negotiation](https://www.rfc-editor.org/rfc/rfc9110#name-proactive-negotiation)
- [RFC 7763 — The `text/markdown` Media Type](https://www.rfc-editor.org/rfc/rfc7763)
- [RFC 8288 — Web Linking](https://www.rfc-editor.org/rfc/rfc8288) (the `Link` header and `rel="alternate"`)
- [Post Content to Markdown](https://github.com/roots/post-content-to-markdown) — the WordPress counterpart this plugin mirrors
