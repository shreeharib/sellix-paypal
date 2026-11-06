# sellix design + routing cheat sheet

`import '../../design/design.dart';` gives every token and widget below.
Rules: colours only from `context.sx`, text only `SxText.*`, spacing `SxSpace.*`, radius `SxRadius.*`, motion `SxMotion.*` (`fast base nav slow pulse stagger curve move spring`). Icons: `TablerIcons.snake_case` (prototype `ti-message-circle` = `TablerIcons.message_circle`). Brand logos: `SxBrandIcon`.
Private widgets in a feature are fine for screen-only pieces (timeline, bar chart): build them from tokens. A `?` below means optional; `onTap: null` means inert (buttons dim).

## Screen frame

```dart
SxScaffold(                       // task screen
  floating: SxBottomCta(label: 'Save stock', onTap: save),   // or SxComposer, floatingMargin: 16
  body: Column(children: [
    SxDetailHeader(title: 'Order', fallback: Routes.orders),
    Expanded(child: SxAsyncView(
      value: ref.watch(orderProvider(id)),
      onRetry: () => ref.invalidate(orderProvider(id)),
      loading: const SxSkeletonList(topHeight: 160),
      isEmpty: (o) => o.items.isEmpty,
      empty: const SxEmptyState(icon: TablerIcons.receipt, title: 'No orders yet'),
      builder: (context, o) => SxScrollList(
        onRefresh: () => ref.refresh(orderProvider(id).future),
        children: [ ... ],
      ),
    )),
  ]),
);
```
Root tabs: same, with `SxRootHeader`, no `floating` (the shell draws the nav). Never a nav and a CTA together.

| Widget | Constructor |
|---|---|
| `SxScaffold` | `body, floating?, floatingMargin=20, statusOnAnchor=false, safeTop=true, background?` |
| `SxScrollList` | `children, onRefresh?, controller?, bottomInset=true, padding?`. Has no side margin: wrap content in `EdgeInsets.symmetric(horizontal: SxSpace.screen)` |
| `sxBottomInset(context)` | double, for your own `ListView.builder` padding |
| `SxAsyncView<T>` | `value, builder(ctx, data), onRetry, loading?, isEmpty?, empty?, errorMessage?`. Keeps data on reload; a failed reload shows a snackbar |
| `SxSkeleton` | `width?, height=16, radius=8` |
| `SxSkeletonList` | `count=5, itemHeight=76, topHeight?` |
| `SxEmptyState` | `icon, title, body?, actionLabel?, onAction?, action?` |
| `SxErrorState` | `error?, message?, onRetry?, retryLabel='Try again'` |
| `sxErrorMessage(error)` | safe text: `ApiException.message`, or a generic line |

## Headers and sections

| Widget | Constructor |
|---|---|
| `SxRootHeader` | `greeting, shopName, onAvatarTap?, onBellTap?, unread=false` |
| `SxDetailHeader` | `title, meta?, metaWidget?, trailing?, fallback='/home', onBack?`. Pass the parent route as `fallback` |
| `SxBackButton` | `fallback='/home', onTap?, onAnchor=false` |
| `SxPageTitle` | `title, subtitle?, trailing?` |
| `SxSectionHeader` | `title, badge?, link?, onLink?` |

## Buttons

| Widget | Constructor |
|---|---|
| `SxButton` | `label, onTap, kind=SxButtonKind.primary, icon?, fullWidth=false, loading=false, semanticLabel?` |
| `SxButtonKind` | `primary secondary signal option optionRecommended ghostAnchor` |
| `SxButtonRow` | `children`: equal widths, secondary left, primary right |
| `SxIconButton` | `icon, semanticLabel, onTap, dot=false, ghost=false, onAnchor=false, child?` |
| `SxLinkButton` | `label, onTap, icon?, color?` |
| `SxBottomCta` | `label, onTap, icon?, loading=false, done=false` |
| `SxPressable` | `child, onTap, semanticLabel?, haptic=true, small=false, onDownChanged?`. Wrap every custom tappable |

## Chips, status, avatars, brand

| Widget | Constructor |
|---|---|
| `SxChip` | `label, tone=SxChipTone.neutral, icon?, dot=false, pulse=false`. Tones: `neutral attention positive error` |
| `SxBadge` | `count, size=22, showZero=false`. 20 in rows, 18 in the nav |
| `SxLivePill` | `state, onTap?, label?`. `SxAgentState`: `live paused waiting` |
| `SxPulseDot` | `size=7, color?, pulse=true` |
| `SxFilterChip` | `label, selected, onTap, badge?, icon?` |
| `SxFilterChips` | `children`: horizontal scroller with the 20 margin |
| `SxPickChip` | `label, selected, onTap, icon?` |
| `SxAvatar` | `name, size=44, onTap?, semanticLabel='Profile'`: merchant |
| `SxCustomerAvatar` | `name, needsYou=false, large=false, channel?` |
| `SxInitialsAvatar` | `name, size=36, background?, foreground?` |
| `sxInitials(name)` | `'@priya.nair'` gives `PN` |
| `SxBrandIcon` | `SxBrandIcon(SxBrand.instagram, size=20, color?)`. `SxBrand`: `instagram whatsapp paypal upi messenger facebook google apple` |
| `SxLogo` | `size=44, surface=SxLogoSurface.page, semanticLabel='sellix'`. Surfaces: `page card anchor photo`. Glyph in light, app tile in dark |

## Cards and rows

| Widget | Constructor |
|---|---|
| `SxCard` | `child, padding?, onTap?, color?` |
| `SxAnchorCard` | `child, onTap?`: no margin |
| `SxHeroCard` | `label, value, valueWidget?, status?, channels=[], change?, changeUp=true, sparkline?, stats=[], onTap?`: has its 20 margin. `SxHeroStat(value:, label:, attention=false)` |
| `SxSparkline` | `values, height=44, color?` |
| `SxRowCard` | `title, meta?, metaWidget?, icon?, leading?, trailing?, onTap?, chevron=true, outlined=false` |
| `SxNeedsYouCard` | `name, reason, message, meta?, channel?, reasonIcon?, note?, secondaryLabel?, onSecondary?, primaryLabel?, onPrimary?, extra?` |
| `SxAiNote` | `SxAiNote('text', icon?)` |
| `SxIconTile` | `icon?, child?, size=44, radius?, background?, foreground?`. Also the product placeholder: never `assets/images` |
| `SxBanner` | `message, tone=SxBannerTone.attention, icon?, action?`. Tones: `attention error neutral` |
| `SxLocalOnlyNote` | `message='Saved on this phone only, not active yet.'` |
| `SxKeyValue` | `label, value?, valueWidget?, divider=false` |
| `SxGroup` | `children`: one card with hairlines |
| `SxListRow` | `title, subtitle?, value?, icon?, leading?, trailing?, onTap?, chevron?, danger=false` |
| `SxSwitchRow` | `title, value, onChanged, subtitle?, icon?, leading?, signal=false` |
| `SxToggle` | `value, onChanged, signal=false, semanticLabel?` |
| `SxChoiceCard` | `title, onTap, subtitle?, icon?, leading?, selected=false, check=false, squareCheck=false` |
| `SxCheck` | `on, square=false` |
| `SxStepsBar` | `total, current (0-based), fraction=0.5` |
| `SxMeter` | `fraction, height=8, color?, background?` |
| `SxTimeChip` | `label, onTap` |

## Inputs

| Widget | Constructor |
|---|---|
| `SxField` | `controller?, label?, hint?, prefix?, trailing?, errorText?, onChanged?, onSubmitted?, keyboardType?, textInputAction?, textCapitalization, inputFormatters?, focusNode?, maxLines=1, minLines?, maxLength?, obscureText=false, autofocus=false, enabled=true, readOnly=false, onTap?, onTile=false, textAlign`. `maxLines > 1` gives the area shape |
| `SxSegmented<T>` | `segments: [SxSegment(value, 'Label')], value, onChanged` |
| `SxStepper` | `value, onChanged, min=0, max?, itemName?` |
| `SxStockRow` | `leading, title, value, onChanged, price?, chip?, min=0, max?, onTap?` |
| `SxVoiceCard` | `stateLabel, onMic, stateIcon?, transcript?, placeholder?, listening=false, micLabel`. Look only: you own recording |
| `SxWaveform` | `active, bars=40` |

## Chat

| Widget | Constructor |
|---|---|
| `SxBubble` | `text, sender, time?, showWho=true`. `SxBubbleSender`: `customer sellix merchant` |
| `SxBubbleLink` | `label, onTap, active=false`: "Show in English" |
| `SxDateSeparator` | `SxDateSeparator('Today')` |
| `SxSystemEvent` | `SxSystemEvent('Paid', icon?)` |
| `SxTypingBubble` | `customer=false`: a real in-flight reply only |
| `SxAttachmentCard` | `leading, title, meta?, outgoing=true, onTap?` |
| `SxEscalationCard` | `body, options, title='sellix paused and asks you', icon?`. `SxEscalationOption(label:, onTap:, recommended=false)` |
| `SxTakeoverStrip` | `sellixOn, onToggle, loading=false, sellixOnLabel, youOnLabel, takeOverLabel, giveBackLabel`: has its margin |
| `SxComposer` | `controller, hint, onSend, onAttach?, attachIcon?, attachLabel='Attach', onChanged?, focusNode?, sending=false, enabled=true` |

## Sheets and snackbars

```dart
final v = await showSxSheet<String>(context, title: 'Pause sellix?', subtitle: '...',
  builder: (sheet) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: SxSpace.s8, children: [
    SxChoiceCard(title: 'For 1 hour', icon: TablerIcons.clock, onTap: () => Navigator.of(sheet).pop('1h')),
  ]));
```
- `showSxSheet<T>(context, builder:, title?, subtitle?, isDismissible=true, scrollable=true)`. Handle, scrim, drag to dismiss, 88% cap and keyboard are handled. Build a `Column`; the body scrolls itself. Pass `scrollable: false` only if your body is a `ListView`. Fields, cards, chips and steppers turn `page`-coloured on a sheet by themselves.
- `showSxConfirm(context, title:, confirmLabel:, body?, cancelLabel='Cancel', confirmIcon?)` returns `Future<bool>`. Use before anything that sends, refunds or changes status.
- `showSxSnack(context, text, icon?, action?, onAction?, sellix?, aboveBar=true, duration=4s)`. `aboveBar: false` on screens with no nav, CTA or composer. Icon is green only when sellix acted (auto-detected from the word "sellix"). With an action it survives navigation; without one it clears on the next navigation. `hideSxSnack()` hides it.

## Motion

`SxFadeUp(child:, index=0)` is the prototype's `.stg` entrance. `SxCountUp(value: int, style:, format?, duration?)` counts integers, so pass minor units and a formatter. `SxSpin(child:)` spins. `SxFadeUp` and `SxCountUp` respect the system's reduce-motion setting.

## Routes (`lib/core/router.dart`)

Use `context.push(...)` for the prototype's `push` and `up` modes (back returns where you came from), `context.go(...)` for `fade`, `reset` and `tab`.

| Kind | Constants and helpers |
|---|---|
| Sign in | `Routes.splash auth welcome prebrief iglogin connecting connected autherror` |
| Onboarding | `Routes.obShop obTalk obRules obHours obPay obTest obStock obLive` |
| Tabs (nav shown) | `Routes.home chats stock orders profile` |
| Task screens (no nav) | `Routes.notifications needs insights morning addproduct customers automations newauto rules channels payments shopprofile hours` |
| With a parameter | `Routes.chat(conversationId) order(orderId) product(variantId) customer(customerId) automation(automationId) editProduct(variantId)` |

Slide-up pages: `iglogin morning addproduct newauto`. Fade pages: `splash auth connecting connected autherror obLive`.

Constructors: `ChatScreen(conversationId)`, `OrderScreen(orderId)`, `ProductScreen(variantId)`, `CustomerScreen(customerId)`, `AutomationScreen(automationId)` take a positional `String`. `AddProductScreen({String? variantId})` is empty for new, set for edit. Keep these when you replace a stub. Other class names: `AuthScreen WelcomeScreen PrebriefScreen IgLoginScreen ConnectingScreen ConnectedScreen AuthErrorScreen SplashScreen ObShopScreen ObTalkScreen ObRulesScreen ObHoursScreen ObPayScreen ObTestScreen ObStockScreen ObLiveScreen HomeScreen NotificationsScreen NeedsScreen InsightsScreen ChatsScreen StockScreen MorningScreen OrdersScreen CustomersScreen AutomationsScreen NewAutoScreen RulesScreen ProfileScreen ChannelsScreen PaymentsScreen ShopProfileScreen HoursScreen`.

### Redirects you must cooperate with

- Signed out: only `splash auth welcome prebrief iglogin connecting autherror`. Anything else goes to `auth`.
- `connecting` and `connected` are never redirected once signed in. `ConnectedScreen` decides the next step: read `onboardingCompletedProvider`, then `go(Routes.home)` or `go(Routes.obShop)`.
- Signed in, onboarding not done: only `ob-*`. Anything else goes to `obShop`.
- **Finishing onboarding:** before leaving `ObLiveScreen` for home, run `await ref.refresh(onboardingCompletedProvider.future);`, or the redirect sends the merchant back to `obShop`.
- Sign out: `ref.read(authControllerProvider.notifier).signOut()` is enough; the redirect handles the rest.

## Other shared state

- `themeModeProvider` (`lib/core/theme_mode.dart`): `ref.read(themeModeProvider.notifier).set(ThemeMode.dark)`.
- `sharedPreferencesProvider` (same file): synchronous `SharedPreferences` for "saved on this phone only" features.
- `navBadgesProvider` (`lib/core/nav_badges.dart`): `ref.read(navBadgesProvider.notifier).update(chatsNeedYou: n, chatsLive: b, ordersToAct: m)`. Push real counts when you load chats, questions or orders, from a callback or after the frame, not during build.
- `ProviderScope` sets `retry: null`: failures reach the screen at once, so every data screen needs its retry button.
