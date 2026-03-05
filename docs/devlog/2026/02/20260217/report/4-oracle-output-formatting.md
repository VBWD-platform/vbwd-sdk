# Oracle Output Formatting for Taro Chat (2026-02-17)

## Summary
Implemented markdown formatting and link handling for Oracle (LLM) output in the Taro chat component. Oracle responses are now displayed with proper formatting, and external links are rendered as clickable hyperlinks with external link icons.

---

## Changes Made

### 1. Markdown Formatter Utility
**File:** `vbwd-frontend/user/plugins/taro/src/utils/markdownFormatter.ts`

Utility functions to parse and convert markdown-style text to HTML:

**Supported Markdown Features:**
- **Bold**: `**text**` or `__text__` → `<strong>`
- **Italic**: `*text*` or `_text_` → `<em>`
- **Code**: `` `text` `` → `<code>` with monospace styling
- **Headings**: `# H1`, `## H2`, `### H3` → `<h1>`, `<h2>`, `<h3>`
- **Links**: `[text](url)` → `<a>` with external link icon and `target="_blank"`
- **Lists**: `- item` or `* item` → `<ul><li>`
- **Numbered Lists**: `1. item` → `<ol><li>`
- **Line Breaks**: `\n` → `<br>`

**Key Functions:**
```typescript
formatMarkdown(text: string): { html: string, hasLinks: boolean }
- Converts markdown to sanitized HTML
- Returns object with formatted HTML and flag for links

hasMarkdown(text: string): boolean
- Detects if text contains markdown formatting

escapeHtml(text: string): string
- Escapes HTML special characters for security
```

### 2. Formatted Message Component
**File:** `vbwd-frontend/user/plugins/taro/src/components/FormattedMessage.vue`

Vue component that renders formatted Oracle messages:

**Features:**
- Accepts `content` prop with markdown-style text
- Renders formatted HTML with `v-html`
- Applies intelligent styling to all markdown elements
- External link icon (`↗`) appears after links
- Responsive typography for mobile devices

**Styling Includes:**
- Proper heading hierarchy with color and sizing
- Syntax highlighting for inline code
- Link styling with hover effects
- List formatting with proper indentation
- External link icons with opacity transitions

### 3. Taro.vue Integration
**Files Modified:** `vbwd-frontend/user/plugins/taro/src/Taro.vue`

**Changes:**
1. Imported `FormattedMessage` component
2. Replaced inline message content with `<FormattedMessage :content="msg.content" />`
3. Enhanced `.message-content` styling with word-wrap properties
4. Increased oracle-message padding for better formatted content display

**Code Changes:**
```vue
<!-- Before -->
<div class="message-content">
  {{ msg.content }}
</div>

<!-- After -->
<div class="message-content">
  <FormattedMessage :content="msg.content" />
</div>
```

---

## Implementation Details

### Security Considerations
1. **HTML Escaping**: All user input is escaped before processing
2. **Link Validation**: Only valid HTTP/HTTPS/relative URLs are converted to links
3. **XSS Protection**: `v-html` is safe because content is pre-sanitized and escaped
4. **Safe Target**: `target="_blank"` with `rel="noopener noreferrer"` for link security

### Link Icon Implementation
The external link icon is implemented using CSS pseudo-element:
```css
external-link::after {
  content: '↗';
  font-size: 0.85em;
  opacity: 0.8;
}
```

### Responsive Design
- Desktop: Full font sizes and formatting
- Mobile: Scaled typography for readability
- Word wrapping enabled for all viewport sizes

---

## Example Markdown Input & Output

### Input (from LLM):
```
# Card Reading Insight

This **reading** reveals three aspects:

1. The *Past* shows growth
2. The *Present* indicates balance
3. The *Future* suggests change

For more details, visit [Tarot Guide](https://example.com/guide)

## Key Meaning
- Symbol: `tarot_card`
- Energy: Transformation
```

### Output (rendered in chat):
```
┌─────────────────────────────────────┐
│ Card Reading Insight                │
│                                     │
│ This **reading** reveals three      │
│ aspects:                            │
│                                     │
│ 1. The *Past* shows growth          │
│ 2. The *Present* indicates balance  │
│ 3. The *Future* suggests change     │
│                                     │
│ For more details, visit             │
│ [Tarot Guide ↗](https://...)        │
│                                     │
│ ## Key Meaning                      │
│ - Symbol: `tarot_card`              │
│ - Energy: Transformation            │
└─────────────────────────────────────┘
```

---

## Files Created

| File | Purpose |
|------|---------|
| `vbwd-frontend/user/plugins/taro/src/utils/markdownFormatter.ts` | Markdown parsing and HTML conversion utility |
| `vbwd-frontend/user/plugins/taro/src/components/FormattedMessage.vue` | Component for rendering formatted messages |

## Files Modified

| File | Changes |
|------|---------|
| `vbwd-frontend/user/plugins/taro/src/Taro.vue` | Import FormattedMessage, replace message rendering, enhance styling |

---

## Testing Checklist

- [ ] Oracle messages with headings display properly
- [ ] Bold and italic text formats correctly
- [ ] Inline code shows with proper styling
- [ ] Links render with external link icon (↗)
- [ ] Links open in new tabs (`target="_blank"`)
- [ ] Lists (ordered and unordered) display properly
- [ ] Multiple line breaks render correctly
- [ ] Hover effects work on links
- [ ] Mobile responsive on < 640px screens
- [ ] Security: No XSS vulnerabilities
- [ ] URL validation prevents non-http links

---

## Styling Features

### Colors & Styling
- **Headings**: Primary color with proper sizing hierarchy
- **Bold**: Bold weight without color change
- **Italic**: Italic style without color change
- **Code**: Monospace font with light background
- **Links**: Primary color with underline, external link icon
- **Lists**: Standard list styling with proper indentation

### Accessibility
- Semantic HTML elements (`<strong>`, `<em>`, `<code>`)
- Proper color contrast for readability
- Text decoration + color for link indication
- Screen reader friendly with external link indication

---

## Performance Notes

- Markdown parsing is done reactively via computed property
- HTML is safe to render with v-html (pre-sanitized)
- No external libraries required (pure regex-based)
- CSS uses scoped styling to avoid conflicts

---

## Future Enhancements

Potential improvements for future iterations:
1. Support for **tables** (| header | data |)
2. **Code blocks** with syntax highlighting (```)
3. **Blockquotes** (> quote)
4. **Strikethrough** (~~text~~)
5. **HTML escaping** improvements for edge cases
6. **Custom markdown** extensions for Taro-specific formatting
7. **Theme-aware colors** that match appearance plugin

---

## Summary

Oracle output is now fully formatted with:
- ✅ Markdown parsing and HTML rendering
- ✅ External links with icons and new tab opening
- ✅ Proper typography hierarchy
- ✅ Security-aware HTML escaping
- ✅ Responsive mobile-friendly design
- ✅ Seamless Vue component integration

The formatting system is extensible and can support additional markdown features in the future.
