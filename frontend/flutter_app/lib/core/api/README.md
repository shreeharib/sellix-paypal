# API layer

Read `ref.read(sellixApiProvider)` / `ref.watch(sellixApiProvider)` from `lib/core/providers.dart`.
Types are in `models.dart`, field for field with the backend. Every method throws `ApiException`
(`message` is safe to show, `statusCode`, `isUnauthorized`).

Sign-in: `authControllerProvider` (`AuthController`: `signInWithInstagram()`, `signOut()`; state
`AuthStatus.signedIn | signedOut`).

Formatting: `lib/core/format.dart`: `money(minor, currency)`, `parseMoneyMinor(text)`,
`minorToInput(minor)`, `formatTime`, `formatDate`, `formatDateTime`, `dayLabel`, `relativeTime`,
`parseBusinessDate`, `businessDateString`, `dateOnly`, `daysBetween`, `addDays`, `isOnBusinessDate`.

## SellixApi

```dart
// Shop
Future<Me> me();
Future<Merchant> updateMerchant({String? name, String? timezone, bool? agentEnabled});
Future<ShopProfile?> shopProfile();
Future<ShopProfile> saveShopProfile(String contentMd);

// Onboarding (rules, hours, tone, UPI live in OnboardingAnswers; a PUT replaces all the answers)
Future<Onboarding> onboarding();
Future<Onboarding> saveOnboarding({required String shopName, required OnboardingAnswers answers, bool complete = false});

// Today
Future<Today> today();
Future<Today> setOpeningStock(List<StockLine> lines);
Future<Today> restock(String variantId, int quantity);
Future<Today> markSoldOut(String variantId);
Future<CounterSaleResponse> recordCounterSale(String variantId, int quantity);
Future<List<StockLine>> parseStockText(String text, {String defaultCurrency = 'INR'});
Future<YesterdayLeftoversResponse> leftovers();
Future<RolloverResponse> applyRollover(List<RolloverItem> items);
Future<RolloverResponse> autoRollover();

// Upcoming stock
Future<List<UpcomingDay>> upcomingStock();
Future<List<UpcomingDay>> setUpcomingStock(DateTime from, DateTime to, List<StockLine> lines);

// Catalog
Future<CatalogSearchResponse> searchCatalog(String query, {int? limit});
Future<List<ProductDetail>> products({String? category});
Future<ProductDetail> product(String productId);
Future<ProductDetail> updateProduct(String productId, ProductUpdate update);
Future<ProductAliasDetail> addProductAlias(String productId, String aliasText);
Future<void> deleteProductAlias(String productId, String aliasId);
Future<List<ShopTypeChoice>> shopTypes();   // GET /v1/shop-types: [{id, label}], the ids for answers.shop_type
Future<ProductSchema> productSchema();   // GET /v1/product-schema: stock modes, shelf-life answers, detail fields, wording

// Orders
Future<List<Order>> orders({List<String>? status, List<String>? paymentStatus, int? limit});
Future<RefundResponse> refundOrder(String orderId, {String? reason, bool restock = true});
Future<CreateInvoiceResponse> createInvoice(String orderId, {String? customerName, String? customerEmail});
Future<Order> markOrderPaid(String orderId, {String method = 'upi', String? referenceId});
Future<Order> completeOrder(String orderId);
Future<Order> cancelOrder(String orderId, {String? reason});
Future<PaymentLinkResponse> paymentLink(String orderId);
Future<Order> updateOrderStatus(String orderId, String status, {String? comment});
Future<List<OrderTimelineEvent>> orderTimeline(String orderId);

// Ask me
Future<List<Question>> questions({String status = 'open'});
Future<Question> answerQuestion(String questionId, String answer, {bool always = false});
Future<Question> closeQuestion(String questionId);

// Chats
Future<List<Conversation>> conversations();
Future<List<ChatMessage>> messages(String conversationId, {int? limit});
Future<AgentSwitch> switchAgent(String conversationId, {required bool active});
Future<List<MemoryFact>> customerMemory(String conversationId);
Future<void> forgetCustomerFact(String conversationId, String key);
Future<List<ChatMessage>> drafts(String conversationId);
Future<void> approveDraft(String conversationId, String messageId, {String? text});
Future<void> discardDraft(String conversationId, String messageId);

// Stories
Future<List<Story>> unconfirmedStories();
Future<void> confirmStory(String storyId, List<String> itemIds);
Future<void> linkPost(String productId, String igMediaId);
Future<void> setMenuImage(String? url);

// Simulator
Future<SimulatorChat> simulatorSend({String text = '', String? quickReply, String customer = 'tester'});
Future<SimulatorChat> simulatorChat({String customer = 'tester'});

// Session
Future<void> logout();
```

## Things that will catch you out

- **Order filters.** `paymentStatus` refuses `'unpaid'` (422). For unpaid orders use
  `status: ['awaiting_payment']`. Most orders read `payment_status` `unpaid`, `paid` or `refunded`.
- **`orders()` returns 50 by default, 200 at most**, with no paging or date filter. Client-side
  insights only see that window.
- **`questions()` has no "all".** Fetch each status you need.
- **Customer on an order.** `Order` has no customer field. Join `order.conversationId` to
  `Conversation.id` for `customerHandle`. `conversationId` can be null.
- **Story item ids** are short refs, not UUIDs. Use `itemRefOf(variantId)` to compare or send them.
  `confirmStory` only accepts items in today's stock.
- **`updateOrderStatus` doesn't validate the transition**, and setting `paid` or `cancelled` through
  it skips payment records and stock release. Use `markOrderPaid` and `cancelOrder` for those.
- **`refundOrder` works for PayPal payments only.** Other orders fail with a 400 message.
- **`neededBy`** is free text, not a date.
- **`StockRow.sold`** excludes counter sales; use `soldTotal`. `opening` excludes restocks; use `made`.
- **`Today.businessDate`** is the shop's day. Use it, not the phone's clock, for "today".
- **`saveShopProfile` and `saveOnboarding`** each create a new shop profile version.
- **Validation errors** (422 from FastAPI) become "Please check <field>: <reason>", which isn't merchant
  copy. Validate limits in the form first: they're noted on the request types in `models.dart`.

## Tests

- `test/support/fake_sellix_api.dart`: `FakeSellixApi()` (some data), `FakeSellixApi.empty()` (new
  shop). Set `failure` for error states and `delay` for loading states; `calls` records the methods
  called. Override with `sellixApiProvider.overrideWithValue(fake)`.
- `test/api/live_contract_test.dart`: real calls, skipped unless `LIVE_API_URL` and `LIVE_TOKEN` are set.

## Running without Meta credentials

`cd backend && just cli issue-token --merchant-id <id>`, then
`flutter run --dart-define=DEV_ACCESS_TOKEN=<token>`. See `AppConfig.devAccessToken`. Debug and profile
builds only.
