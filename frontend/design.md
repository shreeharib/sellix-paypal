# sellix design system: Forest

Version 2.0. Flutter merchant app. Light theme and dark theme.

This file is the single source of truth for the sellix merchant app UI.
All screens and widgets must obey these rules.

---

## 1. Product context

sellix is an AI sales agent for small merchants who sell through Instagram and WhatsApp DMs.

The merchant uses this app to do four jobs:

1. Tell sellix the stock each morning.
2. Monitor sales, orders and chats.
3. Answer the questions that sellix cannot answer alone.
4. Take over a chat at any time.

The merchant uses the app with one hand, between other work. Most sessions are short.
Thus the first view of each screen must show "what needs me now."

---

## 2. Design principles

1. **One job per screen.** Each screen has one primary action. Put it at the bottom, in thumb range.
2. **Color has meaning.** Active green means "sellix does this." Sand means "you must act." No other color has a state meaning.
3. **Calm surfaces, one strong anchor.** Use a mint page and white cards (light theme) or deep green cards (dark theme). Use one anchor block (hero card or voice card) in each view.
4. **Numbers are heroes.** Money and counts use large bold type with tight letter spacing. Labels are small and gray-green.
5. **sellix is honest.** When sellix is not sure, the UI shows this clearly. sellix tells what it did and why.
6. **Space is premium.** Do not fill empty space. Keep 20 px screen margins and generous gaps.
7. **Two themes, one design.** Layout, type, spacing and meaning are the same in both themes. Only the color values change.

---

## 3. Color

The color family comes from one reference: deep forest green, pale mint, warm cream and one active green.
All tokens have a light value and a dark value. Code must read colors by role, never by hex value.

### 3.1 Surface and text tokens

| Token | Light | Dark | Use |
|---|---|---|---|
| `page` | `#E6EEEB` | `#12231F` | Page background |
| `card` | `#FFFFFF` | `#1C322E` | Cards, icon buttons, fields, customer bubbles |
| `tile` | `#F4EEE4` | `#263F3A` | Inner tiles in cards, AI notes, stepper circles |
| `line` | `#DCE5E2` | `#2A433F` | Hairline dividers |
| `lineStrong` | `#CAD6D2` | `#35504B` | Border of secondary buttons, drag handles |
| `textPrimary` | `#10201D` | `#EAF1EE` | Main text |
| `textSecondary` | `#5C6D69` | `#A3B7B2` | Labels, meta text, captions |
| `textTertiary` | `#8A9A96` | `#7A8F8A` | Placeholders and disabled values only |
| `noteText` | `#3E4F4B` | `#C9D6D2` | Text in AI notes |
| `skeleton` | `#DCE5E2` | `#263F3A` | Skeleton blocks for loading |
| `scrim` | `#6610201D` | `#99050B0A` | Area behind bottom sheets and dialogs |

### 3.2 Anchor tokens

The anchor is the one strong block in each view: hero card, voice card, take-over strip, primary buttons and bottom CTA.

| Token | Light | Dark | Use |
|---|---|---|---|
| `anchor` | `#1C3A36` | `#E3ECE9` | Anchor block background |
| `onAnchor` | `#FFFFFF` | `#10201D` | Main text on anchor |
| `onAnchorSecondary` | `#9DB3AE` | `#5C6D69` | Labels on anchor |
| `anchorRaised` | `#2A4945` | `#FFFFFF` | Icon circles on anchor |
| `anchorLine` | `#32514C` | `#C9D6D2` | Dividers on anchor |
| `primary` | `#1C3A36` | `#E3ECE9` | Primary button, bottom CTA, send button |
| `onPrimary` | `#FFFFFF` | `#10201D` | Content on primary |
| `primaryPressed` | `#2A4945` | `#CBD8D4` | Primary in pressed state |

In the light theme the anchor is deep forest green. In the dark theme the anchor is pale mint.
This inversion keeps one strong anchor in each theme. It also matches the reference: a mint card on a deep green frame.

### 3.3 Signal tokens (sellix is active)

| Token | Light | Dark | Use |
|---|---|---|---|
| `signal` | `#4CB06C` | `#4CB06C` | Live dots, mic button, take-over button, go-live arrow circle |
| `onSignal` | `#10201D` | `#10201D` | Icons and text on `signal` fill |
| `signalOnAnchor` | `#A6E0BA` | `#276E40` | Green text on anchor ("sellix" label, "Listening," positive change) |
| `livePill` | `#FFFFFF` | `#FFFFFF` | Agent status pill background |
| `onLivePill` | `#10201D` | `#10201D` | Agent status pill text |

### 3.4 Attention tokens (you must act)

| Token | Light | Dark | Use |
|---|---|---|---|
| `attention` | `#D8B57A` | `#D8B57A` | Count badge, notification dot |
| `onAttention` | `#10201D` | `#10201D` | Text on `attention` |
| `attentionSoft` | `#F5EDE0` | `#2F2A20` | Escalation card, attention chips |
| `attentionLine` | `#E7D7BC` | `#4D412C` | Border of escalation card |
| `attentionText` | `#6E5226` | `#E8CC98` | Titles, chip text and icons on attention surfaces |
| `attentionTextStrong` | `#4F3A18` | `#E2D3B6` | Body text in escalation card |
| `attentionTint` | `#EEDFC6` | `#4A3F2C` | Customer avatar in a needs-you item |
| `attentionOnAnchor` | `#E7C890` | `#9A6F2A` | Attention numbers on anchor (18 px bold or larger only) |

### 3.5 Status tokens

| Token | Light | Dark | Use |
|---|---|---|---|
| `success` | `#4CB06C` | `#4CB06C` | Paid dot |
| `successSoft` | `#DDEFE3` | `#23402F` | "Paid" and "New" chips |
| `successText` | `#1F5A35` | `#A6E0BA` | Text on `successSoft` |
| `error` | `#B4534A` | `#D9776B` | Error dot, destructive icon, field error border |
| `onError` | `#FFFFFF` | `#10201D` | Text on `error` fill |
| `errorSoft` | `#F6E4E1` | `#3A2523` | Error chip and banner |
| `errorText` | `#7A2E26` | `#F0B8AF` | Text on `errorSoft` |

The reference has no red. `error` is a muted clay red in the same earthy family. Use it only for errors.

### 3.6 Component tokens

| Token | Light | Dark | Use |
|---|---|---|---|
| `nav` | `#1C3A36` | `#213A35` | Floating navigation bar |
| `navIcon` | `#8FA6A1` | `#8FA6A1` | Inactive navigation icons |
| `navActive` | `#FFFFFF` | `#E3ECE9` | Active tab pill |
| `onNavActive` | `#10201D` | `#10201D` | Active tab icon and label |
| `bubbleCustomer` | `#FFFFFF` | `#1C322E` | Customer chat bubble |
| `bubbleAi` | `#1C3A36` | `#E3ECE9` | sellix and merchant chat bubbles |
| `onBubbleAi` | `#FFFFFF` | `#10201D` | Text in sellix and merchant bubbles |
| `sendIcon` | `#4CB06C` | `#1C3A36` | Icon in the send button |
| `waveActive` | `#4CB06C` | `#1C3A36` | Active waveform bars |
| `waveSilent` | `#4A6661` | `#A9BAB6` | Silent waveform bars |
| `floatingBorder` | `#00000000` | `#2A433F` | 1 px border of floating bars |
| `floatingShadow` | `#1F10201D` | `#00000000` | Shadow color of floating bars |

### 3.7 Color meaning rules

1. **Signal green means sellix.** Use it only for AI activity: agent live dot, the "sellix" label, voice input, the take-over action and the go-live arrow.
2. **Use `signal` as a fill or dot only.** For green text, use `signalOnAnchor` on anchor surfaces. Do not put green text on `page` or `card`.
3. **Sand means "you must act now."** Use the attention family only for needs-you items, escalation cards and their counts. Do not use it for a state where the customer must act (for example, "Waiting payment").
4. **Text on the `attention` fill is always `onAttention`.**
5. **The agent status pill is always white with a green dot.** This is the "Active" pill from the reference. It is the same in both themes.
6. **Channel icons are monochrome.** Show Instagram and WhatsApp icons in `onAnchor` or `textPrimary`. Do not use their brand colors.
7. **Product swatch colors come from product data.** They are not UI colors. Never use them for UI states.
8. **Approximate color share on a screen:** page, card and tile 80%, anchor 15%, signal and attention under 5%.

### 3.8 Theme rules

1. The app follows the device theme by default. The merchant can change it in Profile (System, Light, Dark).
2. Read every color from the palette by role. A widget must look correct in both themes without code changes.
3. In the dark theme, cards are lighter than the page. Do not use shadows in the dark theme.
4. In the dark theme, floating bars get a 1 px `floatingBorder`. In the light theme, they get a soft shadow.
5. Product photos and swatches do not change between themes.
6. Status bar icons are dark in the light theme and light in the dark theme.

### 3.9 Approved contrast pairs

| Foreground | Background | Use |
|---|---|---|
| `textPrimary` | `page`, `card`, `tile` | Main text |
| `textSecondary` | `page`, `card`, `tile` | Labels and meta text |
| `onAnchor`, `onAnchorSecondary` | `anchor` | Text on anchor blocks |
| `signalOnAnchor` | `anchor` | Green text on anchor |
| `onPrimary` | `primary` | Button labels |
| `onSignal` | `signal` | Mic icon, take-over label, arrow |
| `onAttention` | `attention` | Count badge |
| `attentionText`, `attentionTextStrong` | `attentionSoft`, `attentionTint` | Escalation card, attention chips |
| `successText` | `successSoft` | Paid and New chips |
| `errorText` | `errorSoft` | Error chip and banner |
| `navIcon` | `nav` | Inactive navigation icons |
| `onNavActive` | `navActive` | Active tab |

`textTertiary` is for placeholders and disabled values only. It does not pass 4.5:1.
`attentionOnAnchor` in the dark theme passes only for text 18 px bold or larger.
Do not use pairs that are not in this table without a contrast check (minimum 4.5:1 for text under 18 px).

---

## 4. Typography

### 4.1 Font families

| Family | Use |
|---|---|
| **Satoshi** (variable) | All UI text |
| Noto Sans Tamil | Fallback for Tamil script in customer messages |
| Noto Sans Devanagari | Fallback for Hindi script in customer messages |

Satoshi supports Latin script only. Customers can write in Tamil or Devanagari script. Always set the fallback fonts on every text style.

Get Satoshi from Fontshare. Read the license before release. Use the variable font file, because it gives weight 600. The static Satoshi files have no 600 weight.

Make sure that the `₹` glyph shows correctly. If Satoshi does not include it, the fallback font shows it.

### 4.2 Weights

| Weight | Name | Use |
|---|---|---|
| 500 | Medium | Body text, captions, messages |
| 600 | Semibold | Card titles, buttons, chips, labels |
| 700 | Bold | Titles, hero numbers, stat numbers, counters |

Do not use weights 300, 400 or 900 in the UI. Use a maximum of two weights in one component.
Use the same weights in both themes.

### 4.3 Type scale

| Token | Size / line height | Weight | Letter spacing | Use |
|---|---|---|---|---|
| `display` | 40 / 44 | 700 | −1.5 | Hero money value |
| `titleL` | 30 / 34 | 700 | −1.0 | Screen question or large page title |
| `titleM` | 18 / 24 | 700 | −0.3 | Section headers, merchant name, chat header name |
| `stat` | 20 / 24 | 700 | −0.3 | Stat numbers in hero card |
| `counter` | 17 / 20 | 700 | 0 | Stepper value |
| `labelL` | 16 / 20 | 600 | 0 | Bottom CTA label |
| `bodyStrong` | 15 / 22 | 600 | −0.1 | Card titles, list titles |
| `body` | 15 / 22 | 500 | −0.1 | Chat messages, field text |
| `label` | 14 / 20 | 600 | 0 | Buttons, "See all" links, nav label |
| `bodyS` | 14 / 20 | 500 | 0 | Card body text |
| `caption` | 13 / 18 | 500 | 0 | Labels, meta text, AI notes |
| `micro` | 12 / 16 | 600 | 0 | Chips, badges, time stamps |

### 4.4 Type rules

1. Use sentence case for all text. Do not use Title Case or ALL CAPS.
2. Do not use text smaller than 12 px.
3. Use tabular figures for numbers that change in place (sales, counters). Test that Satoshi renders them. If not, give the number a fixed width.
4. Format money with the merchant locale. Example for India: `NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)` gives `₹1,25,000`.
5. Support system text scale up to 1.3. Clamp the `display` style at 1.2 so that the hero card does not break.
6. Show customer messages exactly as the customer wrote them. Do not change their spelling or script.

---

## 5. Spacing and layout

### 5.1 Spacing scale (4 px grid)

| Token | Value |
|---|---|
| `s4` | 4 |
| `s8` | 8 |
| `s12` | 12 |
| `s16` | 16 |
| `s20` | 20 |
| `s24` | 24 |
| `s32` | 32 |
| `s40` | 40 |
| `s48` | 48 |

### 5.2 Layout constants

| Constant | Value | Rule |
|---|---|---|
| Screen margin | 20 | Left and right edge of all content |
| Card padding | 16 | Inner padding of cards |
| Hero padding | 20 | Inner padding of anchor cards |
| List gap | 8 | Gap between cards in a list |
| Card stack gap | 12 | Gap between unrelated cards (hero to next card) |
| Section top | 24 | Space above a section header |
| Section bottom | 12 | Space between a section header and its content |
| Header height | 64 | Top bar below the status bar |
| Navigation height | 64 | Floating navigation bar |
| Navigation gap | 12 | Space between floating bars and the bottom safe area |
| Bottom inset | 112 | Bottom padding of scroll content above floating bars |

### 5.3 Screen anatomy

```
┌──────────────────────────────┐
│ Status bar (system)          │
│ Header           64          │  avatar + title  |  icon button
│ Anchor block                 │  one per view
│ Supporting cards             │
│ Section header               │  title  |  "See all"
│ List of cards                │
│ ...                          │
│ Bottom inset     112         │
│ ┌──────────────────────────┐ │
│ │ Floating nav or CTA      │ │  floats over content
│ └──────────────────────────┘ │
│ Home indicator (system)      │
└──────────────────────────────┘
```

Rules:

1. Root screens (tabs) show the floating navigation bar.
2. Task screens (stock, chat, order detail) hide the navigation bar. They show a bottom CTA or composer instead.
3. Never show the navigation bar and a bottom CTA together.

---

## 6. Corner radius

| Token | Value | Use |
|---|---|---|
| `tail` | 6 | Tail corner of a chat bubble |
| `tile` | 14 | Icon tiles, product swatches, AI notes |
| `attach` | 18 | Product attachment card in chat |
| `bubble` | 20 | Chat bubbles |
| `card` | 24 | Cards, escalation card |
| `hero` | 28 | Hero card, voice card |
| `sheet` | 32 | Top corners of bottom sheets |
| `pill` | 999 | Buttons, chips, fields, navigation bar |

Concentric rule: inner radius = outer radius − padding. Example: a tile in a card with radius 24 and padding 10 has radius 14.

---

## 7. Elevation

The design is flat. Cards separate from the page by color, not by shadow.

| Theme | Floating bars | Cards |
|---|---|---|
| Light | Shadow: `floatingShadow`, blur 24, offset (0, 8) | No shadow |
| Dark | 1 px `floatingBorder` | No shadow. Card is lighter than page |

Use the floating treatment only on the navigation bar, the bottom CTA and the composer, and only when content scrolls under them.

---

## 8. Icons

1. Use one outline icon set for the full app (Tabler Icons outline is the reference).
2. Do not use filled icons, except for the active state in the navigation bar if the set has a matching filled icon.
3. Sizes: 16 in chips and notes, 20 in buttons and cards, 22 in the navigation bar, 24 in the voice button.
4. Put standalone icon actions in a 44 px `card` circle (icon button).
5. Every icon-only control must have a semantic label.
6. Icons take the text color of their context. Do not give icons their own colors, except `signal` and `attention` dots.

---

## 9. Components

Use the prefix `Sx` for all design system widgets. All colors below are palette roles.

### 9.1 Buttons

| Variant | Background | Content | Height | Use |
|---|---|---|---|---|
| `primary` | `primary` | `onPrimary`, `label` | 44 | Main action in a card |
| `secondary` | transparent, 1 px `lineStrong` border | `textPrimary`, `label` | 44 | Second action next to a primary |
| `signal` | `signal` | `onSignal`, `label` | 36 | Take-over action. Only on anchor surfaces |
| `option` | `card`, or `primary` when recommended | `label` | 44 | Answer options in an escalation card |
| `bottomCta` | `primary`, trailing 48 px `signal` circle with `onSignal` arrow | `onPrimary`, `labelL` | 60 | Screen primary action at the bottom |
| `icon` | `card` circle | 20 px icon in `textPrimary` | 44 | Back, menu, notifications |
| `link` | none | `textPrimary`, `label` | 44 tap area | "See all," "Edit" |

Rules:

1. Use one primary or bottom CTA in each view.
2. When two buttons share a row, they have equal width. Put the secondary on the left and the primary on the right.
3. Pressed state: scale to 0.98 in 120 ms. Primary changes to `primaryPressed`.
4. Do not use disabled buttons. Keep the button active and show the reason after a tap.
5. Button labels start with a verb and have one to four words ("Hold price," "Confirm and go live").

### 9.2 Chips and badges

| Type | Background | Text | Example |
|---|---|---|---|
| Neutral | `card` or `tile` | `textPrimary` | "Waiting payment," date chip |
| Attention | `attentionSoft` | `attentionText` | "Price ask," "Sold out" |
| Positive | `successSoft` | `successText` | "Paid," "New" |
| Error | `errorSoft` | `errorText` | "Payment failed" |
| Agent status | `livePill` with 7 px `signal` dot | `onLivePill` | "Agent live" |
| Count badge | `attention` | `onAttention` | "3" |

Size: `micro` text, padding 5 × 10, radius `pill`. Dots inside chips are 6 to 7 px.

### 9.3 Avatars

1. Merchant: 44 px circle. Show the shop logo. If there is no logo, show initials in `onAnchor` on `anchor`.
2. Customer in lists: 36 px circle with initials. Use `attentionTint` with `attentionText` when the item needs the merchant. Use `tile` with `textPrimary` in other cases.
3. A 16 px channel badge (Instagram or WhatsApp, monochrome) sits at the bottom right of customer avatars in chat lists.

### 9.4 Headers

Root header: avatar 44, gap 12, `caption` ("Good morning") above `titleM` (shop name). Notification icon button on the right. A 8 px `attention` dot shows unread items.

Detail header: back icon button, gap 12, `titleM` name above `caption` meta (channel and language mix). Menu icon button on the right.

### 9.5 Hero card (sales)

- Background `anchor`, radius `hero`, padding 20, margin 20 left and right.
- Top row: agent status pill on the left. Channel icons in 30 px `anchorRaised` circles on the right.
- `caption` label in `onAnchorSecondary`, 20 px below the top row.
- Money value in `display`, `onAnchor`.
- Change value in `caption`: `signalOnAnchor` if up, `onAnchorSecondary` if down. Do not use red for a decrease.
- Divider `anchorLine`, 18 px above a 3-column stat row (`stat` value, `micro` label in `onAnchorSecondary`).
- The "Need you" stat uses `attentionOnAnchor`.

### 9.6 Agent status

| State | Dot | Label | Meaning |
|---|---|---|---|
| Live | `signal`, slow pulse | "Agent live" | sellix answers chats |
| Paused | `attention` | "Agent paused" | Merchant paused sellix |
| Waiting for stock | `textTertiary` | "Waiting for stock" | Merchant did not set stock today |

The pill is always `livePill` with `onLivePill` text. Only the dot changes.

### 9.7 Section header

`titleM` title on the left. Optional count badge after the title. `label` link ("See all") on the right. Padding: 24 top, 12 bottom, 22 left and right.

### 9.8 Row card

`card`, padding 14 × 16. 44 px `tile` icon tile (radius `tile`) on the left. `bodyStrong` title above `caption` meta. 20 px chevron in `textSecondary` on the right. Use for status summaries (for example, "Stock set at 8:10 AM").

### 9.9 Needs-you card

- `card`, padding 16.
- Top row: customer avatar, name (`bodyStrong`), meta (`micro` in `textSecondary`, channel and time), attention chip with the reason.
- Customer message in `bodyS`, in quotes, 12 px below.
- AI note below the message (see 9.10).
- Button row: secondary on the left, primary on the right.
- Show a maximum of three needs-you cards on Home. Put the rest behind "See all."

### 9.10 AI note

`tile` background, radius `tile`, padding 10 × 12. Sparkle icon 16 px, then `caption` text in `noteText`. sellix speaks in first person. The note says what sellix did and why. Example: "Below your ₹1,500 floor. I did not reply."

### 9.11 Chat bubbles

| Sender | Side | Background | Text | Corners |
|---|---|---|---|---|
| Customer | Left | `bubbleCustomer` | `textPrimary`, `body` | 20, 20, 20, 6 (bottom left is the tail) |
| sellix | Right | `bubbleAi` | `onBubbleAi`, `body` | 20, 20, 6, 20 (bottom right is the tail) |
| Merchant | Right | `bubbleAi` | `onBubbleAi`, `body` | Same as sellix |

- sellix bubbles start with a `micro` label "sellix" with a sparkle icon, in `signalOnAnchor`.
- Merchant bubbles start with a `micro` label "You" in `onAnchorSecondary`.
- Maximum bubble width is 75% of the screen.
- Gap between bubbles is 10. Date separator is `micro`, centered, `textSecondary`.
- If the customer writes in a language mix, show a "Show in English" link (`micro`) below the bubble.

### 9.12 Escalation card (in chat)

- Background `attentionSoft`, 1 px `attentionLine` border, radius `card`, padding 16.
- Title row: hand-stop icon 18 px and `label` text in `attentionText` ("sellix paused and asks you").
- Body in `bodyS`, `attentionTextStrong`. It states the problem and the question.
- Two to three `option` buttons in a column, gap 8. The recommended option is first and uses `primary`. The last option is always "Write my own reply."

### 9.13 Product attachment card

`card`, radius `attach`, padding 10. 48 px product photo or swatch (radius `tile`), then `label` name above `micro` meta (variant, price, stock left).

### 9.14 Composer

`card` field, radius `pill`, padding 16 × 20, placeholder "Reply as {merchant name}" in `textTertiary`. 52 px `primary` send button with a `sendIcon` icon. Position: floats 12 px above the bottom safe area.

### 9.15 Take-over strip

`anchor` pill below the chat header. Pulse dot (`signal`) and `caption` "sellix is on this chat" in `onAnchor`. `signal` button "Take over" on the right. When the merchant takes over, the strip changes to "You are on this chat" with a button "Give back to sellix."

### 9.16 Voice capture card

`anchor` card, radius `hero`, padding 20. State label with dot ("Listening") in `signalOnAnchor`. Live transcript in `body` 16 px, `onAnchor`. Waveform bars (3 px wide, radius 2, `waveActive` for active, `waveSilent` for silent) on the left. 56 px `signal` microphone button with `onSignal` icon on the right.

### 9.17 Stock row with stepper

`card`, padding 12 × 14. 44 px product swatch or photo. `bodyStrong` name above price (`caption`) or a chip ("Sold out," "New"). Stepper on the right: 32 px `tile` circles with minus and plus, `counter` value with 22 px width between them. A zero value shows in `textTertiary`.

### 9.18 Floating navigation bar

- `nav` pill, height 64, 20 from the left and right edges, 12 above the bottom safe area.
- Five tabs: Home, Chats, Stock, Orders, Profile.
- Active tab: `navActive` pill with 20 px icon and `label` text in `onNavActive`.
- Inactive tabs: 22 px icon in `navIcon`, no label.
- A 8 px `signal` dot on Chats shows live AI chats. A count badge on Chats shows needs-you items.
- The active pill moves to the selected tab in 240 ms.

### 9.19 Fields

`card`, radius `pill`, height 52, padding 16 × 20, `body` text. Focus: 1.5 px `textPrimary` border. Error: 1.5 px `error` border and `caption` text in `errorText` below the field.

### 9.20 Bottom sheet

`card` background, top radius `sheet`, drag handle 36 × 4 in `lineStrong`, `scrim` behind. Title in `titleM`. Primary action at the bottom. Use for edit forms and confirmations.

### 9.21 Snackbar

Floating `anchor` pill, `bodyS` text in `onAnchor`, optional `label` action in `signalOnAnchor`. It stays for 4 seconds. Example: "Stock is live. sellix is on 2 chats."

### 9.22 Empty, loading and error states

- Empty: 44 px `tile` icon tile, `titleM` headline that invites action, one `bodyS` line, one primary button. Example: "Set today's stock."
- Loading: `skeleton` blocks with the same shapes and radii as the real content. Do not use spinners on full screens.
- Error: `errorSoft` banner with `errorText`. Say what happened, then what to do.

---

## 10. Screens and flow

### 10.1 Navigation map

```
Tabs:  Home | Chats | Stock | Orders | Profile

Home ──► Needs-you card ──► Chat detail (escalation card in focus)
Home ──► Stock row card ──► Morning stock
Home ──► Hero card ──────► Sales detail
Chats ─► Chat detail ────► Product picker (sheet), Order (sheet)
Orders ► Order detail
Profile ► Agent rules, Channels, Payments, Languages, Appearance
Push notification "needs you" ──► Chat detail
Morning push "What is in stock today?" ──► Morning stock
```

### 10.2 Daily flow

1. Morning push opens Morning stock.
2. The merchant speaks or types the stock. sellix makes the list.
3. The merchant corrects counts and taps "Confirm and go live."
4. Home shows "Agent live." sellix answers chats.
5. When sellix is not sure, it pauses that chat and sends a needs-you push.
6. The merchant selects an option or writes a reply. sellix continues.
7. sellix collects payment. The order moves to "Paid."

### 10.3 Screen templates (top to bottom)

**Home:** root header, sales hero card, stock row card (or an anchor card "Set today's stock" with a `signal` microphone button if stock is not set), "Needs you" section (maximum 3 cards), "Live chats" section (rows), "Recent orders" section (rows), floating navigation.

**Chats:** title "Chats" in `titleL`, search field, filter chips (All, Needs you, Taking order, Waiting payment, Done), list rows. Needs-you rows stay at the top with an `attention` dot.

**Chat detail:** detail header, take-over strip, message list, escalation card when sellix is paused, composer.

**Morning stock:** back button and date chip, `titleL` question "What is in stock today?", `caption` helper text, voice capture card, "sellix found" section with stock rows, bottom CTA "Confirm and go live."

**Orders:** title in `titleL`, period chips (Today, This week, This month), anchor summary card (total and count), order rows (swatch, customer, amount, status chip).

**Order detail:** detail header, `display` amount, status chip, items list, payment card (method, status, link), timeline, bottom CTA (for example, "Mark as shipped").

**Profile:** merchant card, groups of row cards: Agent rules (price floor, cash on delivery, delivery areas, working hours, "Ask me when"), Channels, Payments, Languages, Appearance (System, Light, Dark), Notifications.

**Onboarding:** one step per screen. Steps: connect Instagram, connect WhatsApp, connect payments, set rules, set first stock. Progress shows as five short pills at the top (`primary` for done, `lineStrong` for not done).

---

## 11. Motion and haptics

| Token | Value | Use |
|---|---|---|
| `fast` | 120 ms | Press scale, chip select |
| `base` | 200 ms | Cards appear, state changes |
| `nav` | 240 ms | Navigation pill movement |
| `slow` | 320 ms | Sheets, screen-level changes |
| `pulse` | 1600 ms loop | Agent live dot |
| `stagger` | 40 ms | Delay between list items that appear |
| `curve` | `Curves.easeOutCubic` | Default |
| `move` | `Curves.easeInOutCubic` | Elements that move position |

Rules:

1. New escalation card: fade in and move up 12 px in `base`.
2. Stock rows from voice: appear one by one, `stagger` apart.
3. Hero money value: count up in `slow` when the value changes.
4. A theme change does not animate colors. The theme changes immediately.
5. When the system "reduce motion" setting is on, remove pulse, count-up and stagger.

Haptics:

| Event | Haptic |
|---|---|
| Stepper change, chip select | `HapticFeedback.selectionClick()` |
| Button tap | `HapticFeedback.lightImpact()` |
| Confirm and go live, take over | `HapticFeedback.mediumImpact()` |

---

## 12. Content and voice

1. System UI does not say "I." It uses "you" and "your."
2. sellix says "I" only in AI notes, escalation cards and AI chat bubbles.
3. sellix tells what it did, then why. Example: "I did not reply. The price is below your floor."
4. Do not use "please," "successfully" or exclamation marks in system text.
5. Errors say what happened, then what to do. Example: "Payment link expired. Send a new link."
6. Use short, simple words. Many merchants read English as a second language.
7. Write customer names and product names exactly as the merchant or customer wrote them.

---

## 13. Accessibility

1. Minimum tap target is 44 × 44.
2. Do not show a state with color only. Each colored state also has a text label or an icon.
3. Every icon-only control has a `Semantics` label.
4. Announce new needs-you items and "Agent paused" with `SemanticsService.announce`.
5. Test all screens at text scale 1.3, in both themes, with TalkBack and VoiceOver.

---

## 14. Flutter implementation

### 14.1 Fonts in pubspec.yaml

Use the file names from your downloads.

```yaml
flutter:
  fonts:
    - family: Satoshi
      fonts:
        - asset: assets/fonts/Satoshi-Variable.ttf
        - asset: assets/fonts/Satoshi-VariableItalic.ttf
          style: italic
    - family: NotoSansTamil
      fonts:
        - asset: assets/fonts/NotoSansTamil-Variable.ttf
    - family: NotoSansDevanagari
      fonts:
        - asset: assets/fonts/NotoSansDevanagari-Variable.ttf
```

### 14.2 lib/design/tokens/sx_palette.dart

```dart
import 'package:flutter/material.dart';

@immutable
class SxPalette extends ThemeExtension<SxPalette> {
  const SxPalette({
    required this.page,
    required this.card,
    required this.tile,
    required this.line,
    required this.lineStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.noteText,
    required this.skeleton,
    required this.scrim,
    required this.anchor,
    required this.onAnchor,
    required this.onAnchorSecondary,
    required this.anchorRaised,
    required this.anchorLine,
    required this.primary,
    required this.onPrimary,
    required this.primaryPressed,
    required this.signal,
    required this.onSignal,
    required this.signalOnAnchor,
    required this.livePill,
    required this.onLivePill,
    required this.attention,
    required this.onAttention,
    required this.attentionSoft,
    required this.attentionLine,
    required this.attentionText,
    required this.attentionTextStrong,
    required this.attentionTint,
    required this.attentionOnAnchor,
    required this.success,
    required this.successSoft,
    required this.successText,
    required this.error,
    required this.onError,
    required this.errorSoft,
    required this.errorText,
    required this.nav,
    required this.navIcon,
    required this.navActive,
    required this.onNavActive,
    required this.bubbleCustomer,
    required this.bubbleAi,
    required this.onBubbleAi,
    required this.sendIcon,
    required this.waveActive,
    required this.waveSilent,
    required this.floatingBorder,
    required this.floatingShadow,
  });

  final Color page, card, tile, line, lineStrong;
  final Color textPrimary, textSecondary, textTertiary, noteText, skeleton, scrim;
  final Color anchor, onAnchor, onAnchorSecondary, anchorRaised, anchorLine;
  final Color primary, onPrimary, primaryPressed;
  final Color signal, onSignal, signalOnAnchor, livePill, onLivePill;
  final Color attention, onAttention, attentionSoft, attentionLine;
  final Color attentionText, attentionTextStrong, attentionTint, attentionOnAnchor;
  final Color success, successSoft, successText;
  final Color error, onError, errorSoft, errorText;
  final Color nav, navIcon, navActive, onNavActive;
  final Color bubbleCustomer, bubbleAi, onBubbleAi, sendIcon;
  final Color waveActive, waveSilent, floatingBorder, floatingShadow;

  static const light = SxPalette(
    page: Color(0xFFE6EEEB),
    card: Color(0xFFFFFFFF),
    tile: Color(0xFFF4EEE4),
    line: Color(0xFFDCE5E2),
    lineStrong: Color(0xFFCAD6D2),
    textPrimary: Color(0xFF10201D),
    textSecondary: Color(0xFF5C6D69),
    textTertiary: Color(0xFF8A9A96),
    noteText: Color(0xFF3E4F4B),
    skeleton: Color(0xFFDCE5E2),
    scrim: Color(0x6610201D),
    anchor: Color(0xFF1C3A36),
    onAnchor: Color(0xFFFFFFFF),
    onAnchorSecondary: Color(0xFF9DB3AE),
    anchorRaised: Color(0xFF2A4945),
    anchorLine: Color(0xFF32514C),
    primary: Color(0xFF1C3A36),
    onPrimary: Color(0xFFFFFFFF),
    primaryPressed: Color(0xFF2A4945),
    signal: Color(0xFF4CB06C),
    onSignal: Color(0xFF10201D),
    signalOnAnchor: Color(0xFFA6E0BA),
    livePill: Color(0xFFFFFFFF),
    onLivePill: Color(0xFF10201D),
    attention: Color(0xFFD8B57A),
    onAttention: Color(0xFF10201D),
    attentionSoft: Color(0xFFF5EDE0),
    attentionLine: Color(0xFFE7D7BC),
    attentionText: Color(0xFF6E5226),
    attentionTextStrong: Color(0xFF4F3A18),
    attentionTint: Color(0xFFEEDFC6),
    attentionOnAnchor: Color(0xFFE7C890),
    success: Color(0xFF4CB06C),
    successSoft: Color(0xFFDDEFE3),
    successText: Color(0xFF1F5A35),
    error: Color(0xFFB4534A),
    onError: Color(0xFFFFFFFF),
    errorSoft: Color(0xFFF6E4E1),
    errorText: Color(0xFF7A2E26),
    nav: Color(0xFF1C3A36),
    navIcon: Color(0xFF8FA6A1),
    navActive: Color(0xFFFFFFFF),
    onNavActive: Color(0xFF10201D),
    bubbleCustomer: Color(0xFFFFFFFF),
    bubbleAi: Color(0xFF1C3A36),
    onBubbleAi: Color(0xFFFFFFFF),
    sendIcon: Color(0xFF4CB06C),
    waveActive: Color(0xFF4CB06C),
    waveSilent: Color(0xFF4A6661),
    floatingBorder: Color(0x00000000),
    floatingShadow: Color(0x1F10201D),
  );

  static const dark = SxPalette(
    page: Color(0xFF12231F),
    card: Color(0xFF1C322E),
    tile: Color(0xFF263F3A),
    line: Color(0xFF2A433F),
    lineStrong: Color(0xFF35504B),
    textPrimary: Color(0xFFEAF1EE),
    textSecondary: Color(0xFFA3B7B2),
    textTertiary: Color(0xFF7A8F8A),
    noteText: Color(0xFFC9D6D2),
    skeleton: Color(0xFF263F3A),
    scrim: Color(0x99050B0A),
    anchor: Color(0xFFE3ECE9),
    onAnchor: Color(0xFF10201D),
    onAnchorSecondary: Color(0xFF5C6D69),
    anchorRaised: Color(0xFFFFFFFF),
    anchorLine: Color(0xFFC9D6D2),
    primary: Color(0xFFE3ECE9),
    onPrimary: Color(0xFF10201D),
    primaryPressed: Color(0xFFCBD8D4),
    signal: Color(0xFF4CB06C),
    onSignal: Color(0xFF10201D),
    signalOnAnchor: Color(0xFF276E40),
    livePill: Color(0xFFFFFFFF),
    onLivePill: Color(0xFF10201D),
    attention: Color(0xFFD8B57A),
    onAttention: Color(0xFF10201D),
    attentionSoft: Color(0xFF2F2A20),
    attentionLine: Color(0xFF4D412C),
    attentionText: Color(0xFFE8CC98),
    attentionTextStrong: Color(0xFFE2D3B6),
    attentionTint: Color(0xFF4A3F2C),
    attentionOnAnchor: Color(0xFF9A6F2A),
    success: Color(0xFF4CB06C),
    successSoft: Color(0xFF23402F),
    successText: Color(0xFFA6E0BA),
    error: Color(0xFFD9776B),
    onError: Color(0xFF10201D),
    errorSoft: Color(0xFF3A2523),
    errorText: Color(0xFFF0B8AF),
    nav: Color(0xFF213A35),
    navIcon: Color(0xFF8FA6A1),
    navActive: Color(0xFFE3ECE9),
    onNavActive: Color(0xFF10201D),
    bubbleCustomer: Color(0xFF1C322E),
    bubbleAi: Color(0xFFE3ECE9),
    onBubbleAi: Color(0xFF10201D),
    sendIcon: Color(0xFF1C3A36),
    waveActive: Color(0xFF1C3A36),
    waveSilent: Color(0xFFA9BAB6),
    floatingBorder: Color(0xFF2A433F),
    floatingShadow: Color(0x00000000),
  );

  // Theme changes do not animate (DESIGN.md 11, rule 4).
  @override
  SxPalette copyWith() => this;

  @override
  SxPalette lerp(covariant SxPalette? other, double t) =>
      (other == null || t < 0.5) ? this : other;
}

extension SxContext on BuildContext {
  SxPalette get sx => Theme.of(this).extension<SxPalette>()!;
}
```

### 14.3 lib/design/tokens/sx_text.dart

Text styles have no color. Add the color from the palette with `copyWith(color: ...)`.

```dart
import 'dart:ui' show FontFeature, FontVariation;
import 'package:flutter/material.dart';

abstract final class SxText {
  static const _f = 'Satoshi';
  static const _fb = ['NotoSansTamil', 'NotoSansDevanagari'];
  static const _tnum = [FontFeature.tabularFigures()];

  static const display = TextStyle(
    fontFamily: _f, fontFamilyFallback: _fb,
    fontSize: 40, height: 44 / 40, letterSpacing: -1.5,
    fontWeight: FontWeight.w700, fontVariations: [FontVariation('wght', 700)],
    fontFeatures: _tnum,
  );
  static const titleL = TextStyle(
    fontFamily: _f, fontFamilyFallback: _fb,
    fontSize: 30, height: 34 / 30, letterSpacing: -1.0,
    fontWeight: FontWeight.w700, fontVariations: [FontVariation('wght', 700)],
  );
  static const titleM = TextStyle(
    fontFamily: _f, fontFamilyFallback: _fb,
    fontSize: 18, height: 24 / 18, letterSpacing: -0.3,
    fontWeight: FontWeight.w700, fontVariations: [FontVariation('wght', 700)],
  );
  static const stat = TextStyle(
    fontFamily: _f, fontFamilyFallback: _fb,
    fontSize: 20, height: 24 / 20, letterSpacing: -0.3,
    fontWeight: FontWeight.w700, fontVariations: [FontVariation('wght', 700)],
    fontFeatures: _tnum,
  );
  static const counter = TextStyle(
    fontFamily: _f, fontFamilyFallback: _fb,
    fontSize: 17, height: 20 / 17,
    fontWeight: FontWeight.w700, fontVariations: [FontVariation('wght', 700)],
    fontFeatures: _tnum,
  );
  static const labelL = TextStyle(
    fontFamily: _f, fontFamilyFallback: _fb,
    fontSize: 16, height: 20 / 16,
    fontWeight: FontWeight.w600, fontVariations: [FontVariation('wght', 600)],
  );
  static const bodyStrong = TextStyle(
    fontFamily: _f, fontFamilyFallback: _fb,
    fontSize: 15, height: 22 / 15, letterSpacing: -0.1,
    fontWeight: FontWeight.w600, fontVariations: [FontVariation('wght', 600)],
  );
  static const body = TextStyle(
    fontFamily: _f, fontFamilyFallback: _fb,
    fontSize: 15, height: 22 / 15, letterSpacing: -0.1,
    fontWeight: FontWeight.w500, fontVariations: [FontVariation('wght', 500)],
  );
  static const label = TextStyle(
    fontFamily: _f, fontFamilyFallback: _fb,
    fontSize: 14, height: 20 / 14,
    fontWeight: FontWeight.w600, fontVariations: [FontVariation('wght', 600)],
  );
  static const bodyS = TextStyle(
    fontFamily: _f, fontFamilyFallback: _fb,
    fontSize: 14, height: 20 / 14,
    fontWeight: FontWeight.w500, fontVariations: [FontVariation('wght', 500)],
  );
  static const caption = TextStyle(
    fontFamily: _f, fontFamilyFallback: _fb,
    fontSize: 13, height: 18 / 13,
    fontWeight: FontWeight.w500, fontVariations: [FontVariation('wght', 500)],
  );
  static const micro = TextStyle(
    fontFamily: _f, fontFamilyFallback: _fb,
    fontSize: 12, height: 16 / 12,
    fontWeight: FontWeight.w600, fontVariations: [FontVariation('wght', 600)],
  );

  static const textTheme = TextTheme(
    displayLarge: display,
    headlineMedium: titleL,
    titleMedium: titleM,
    bodyLarge: body,
    bodyMedium: bodyS,
    bodySmall: caption,
    labelLarge: label,
    labelSmall: micro,
  );
}
```

### 14.4 lib/design/tokens/sx_layout.dart

```dart
import 'package:flutter/animation.dart';

abstract final class SxSpace {
  static const s4 = 4.0;
  static const s8 = 8.0;
  static const s12 = 12.0;
  static const s16 = 16.0;
  static const s20 = 20.0;
  static const s24 = 24.0;
  static const s32 = 32.0;
  static const s40 = 40.0;
  static const s48 = 48.0;

  static const screen = 20.0;
  static const card = 16.0;
  static const hero = 20.0;
  static const listGap = 8.0;
  static const stackGap = 12.0;
  static const sectionTop = 24.0;
  static const sectionBottom = 12.0;
  static const headerHeight = 64.0;
  static const navHeight = 64.0;
  static const navGap = 12.0;
  static const bottomInset = 112.0;
}

abstract final class SxRadius {
  static const tail = 6.0;
  static const tile = 14.0;
  static const attach = 18.0;
  static const bubble = 20.0;
  static const card = 24.0;
  static const hero = 28.0;
  static const sheet = 32.0;
  static const pill = 999.0;
}

abstract final class SxMotion {
  static const fast = Duration(milliseconds: 120);
  static const base = Duration(milliseconds: 200);
  static const nav = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 320);
  static const pulse = Duration(milliseconds: 1600);
  static const stagger = Duration(milliseconds: 40);
  static const curve = Curves.easeOutCubic;
  static const move = Curves.easeInOutCubic;
}
```

### 14.5 lib/design/sx_theme.dart

```dart
import 'package:flutter/material.dart';
import 'tokens/sx_palette.dart';
import 'tokens/sx_text.dart';
import 'tokens/sx_layout.dart';

ThemeData buildSellixTheme(SxPalette p, Brightness b) {
  final scheme = ColorScheme(
    brightness: b,
    primary: p.primary,
    onPrimary: p.onPrimary,
    secondary: p.signal,
    onSecondary: p.onSignal,
    error: p.error,
    onError: p.onError,
    surface: p.card,
    onSurface: p.textPrimary,
    surfaceTint: Colors.transparent,
  );

  OutlineInputBorder border(Color c, double w) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(SxRadius.pill),
        borderSide: w == 0 ? BorderSide.none : BorderSide(color: c, width: w),
      );

  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    extensions: [p],
    scaffoldBackgroundColor: p.page,
    fontFamily: 'Satoshi',
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    textTheme: SxText.textTheme.apply(
      bodyColor: p.textPrimary,
      displayColor: p.textPrimary,
    ),
    iconTheme: IconThemeData(color: p.textPrimary, size: 20),
    dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.card,
      hintStyle: SxText.body.copyWith(color: p.textTertiary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      border: border(p.textPrimary, 0),
      enabledBorder: border(p.textPrimary, 0),
      focusedBorder: border(p.textPrimary, 1.5),
      errorBorder: border(p.error, 1.5),
      focusedErrorBorder: border(p.error, 1.5),
      errorStyle: SxText.caption.copyWith(color: p.errorText),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.anchor,
      contentTextStyle: SxText.bodyS.copyWith(color: p.onAnchor),
      actionTextColor: p.signalOnAnchor,
      behavior: SnackBarBehavior.floating,
      shape: const StadiumBorder(),
      elevation: 0,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.card,
      modalBarrierColor: p.scrim,
      elevation: 0,
      showDragHandle: true,
      dragHandleColor: p.lineStrong,
      dragHandleSize: const Size(36, 4),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(SxRadius.sheet)),
      ),
    ),
  );
}

final sellixLight = buildSellixTheme(SxPalette.light, Brightness.light);
final sellixDark = buildSellixTheme(SxPalette.dark, Brightness.dark);
```

### 14.6 App setup

```dart
MaterialApp(
  theme: sellixLight,
  darkTheme: sellixDark,
  themeMode: ThemeMode.system, // Replace with the merchant's Appearance setting.
  home: const HomeScreen(),
);
```

### 14.7 Floating bar decoration

```dart
BoxDecoration sxFloating(SxPalette p, Color fill) => BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(SxRadius.pill),
      border: Border.all(color: p.floatingBorder),
      boxShadow: [
        BoxShadow(color: p.floatingShadow, blurRadius: 24, offset: const Offset(0, 8)),
      ],
    );
```

---

## 15. Do and do not

| Do | Do not |
|---|---|
| Read colors from `context.sx` by role | Write hex values in widgets |
| Use signal green only for sellix activity | Use green as a general accent |
| Use `signalOnAnchor` for green text | Put `signal` green text on cards or page |
| Use sand only when the merchant must act | Use sand for warnings that need no action |
| Use one anchor block in each view | Stack two anchor cards |
| Keep 20 px screen margins | Push cards to the screen edge |
| Use weights 500, 600 and 700 | Use 800 or 900 for labels |
| Put the primary action at the bottom | Put the primary action in the header |
| Show customer text exactly as written | Correct or translate customer text in place |
| Separate cards with color | Add shadows to cards |
| Use monochrome channel icons | Use Instagram or WhatsApp brand colors |
| Use skeleton blocks for loading | Use a full-screen spinner |
| Test every screen in light and dark | Design in one theme only |