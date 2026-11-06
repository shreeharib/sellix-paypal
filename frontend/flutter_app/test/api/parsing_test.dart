import 'package:flutter_test/flutter_test.dart';
import 'package:sellix_merchant/core/api/models.dart';

const _uuid = '3f2a1b00-1111-4222-8333-444455556666';
const _uuid2 = '9c8d7e00-1111-4222-8333-444455556666';
const _at = '2026-11-05T10:30:00+00:00';

Map<String, dynamic> _stockRow() => {
  'variant_id': _uuid,
  'product': 'Plum cake',
  'variant': '500 g',
  'price_minor': 45000,
  'currency': 'INR',
  'opening': 10,
  'restocked': 2,
  'held': 1,
  'sold': 3,
  'counter_sales': 2,
  'available': 6,
  'stock_mode': 'inventory',
  'shelf_life_days': 3,
};

Map<String, dynamic> _today() => {
  'business_date': '2026-11-05',
  'agent_enabled': true,
  'stock': [_stockRow()],
  'open_questions': 2,
  'orders_awaiting_payment': 1,
  'orders_paid': 4,
  'revenue_minor_by_currency': {'INR': 180000, 'USD': 1250},
};

Map<String, dynamic> _variant() => {
  'id': _uuid,
  'sku': null,
  'name': '500 g',
  'price_minor': 45000,
  'compare_at_price_minor': null,
  'cost_price_minor': 20000,
  'currency': 'INR',
  'stock_mode': null,
  'shelf_life_days': null,
  'attributes': {'eggless': true},
  'is_active': true,
};

Map<String, dynamic> _order() => {
  'id': _uuid,
  'number': 1046,
  'status': 'paid',
  'currency': 'INR',
  'total_minor': 90000,
  'conversation_id': _uuid2,
  'created_at': _at,
  'paid_at': _at,
  'hold_expires_at': null,
  'items': [
    {'product': 'Plum cake', 'variant': null, 'quantity': 2, 'unit_price_minor': 45000},
  ],
  'payment_status': 'paid',
  'fulfilment_status': 'in_production',
  'fulfilment_method': 'delivery',
  'channel': 'instagram',
  'delivery_address': '21 Test Street',
  'customer_note': 'Call before',
  'order_number': 'ORD-1046',
  'fulfilment': 'delivery',
  'delivery_type': 'delivery',
  'source_channel': 'instagram',
  'total_amount_minor': 90000,
  'needed_by': '2026-11-06 6 pm',
  'notes': 'Call before',
};

void main() {
  group('shop', () {
    test('Me, with a channel', () {
      final me = Me.fromJson({
        'user_id': _uuid,
        'merchant': {
          'id': _uuid2,
          'name': 'Test Bakery',
          'timezone': 'Asia/Kolkata',
          'agent_enabled': true,
        },
        'role': 'owner',
        'channels': [
          {
            'channel': 'instagram',
            'username': null,
            'status': 'active',
            'token_expires_at': _at,
          },
        ],
        'onboarding_completed': false,
      });
      expect(me.merchant.name, 'Test Bakery');
      expect(me.channels.single.username, isNull);
      expect(me.channels.single.tokenExpiresAt, DateTime.utc(2026, 11, 5, 10, 30));
      expect(me.onboardingCompleted, isFalse);
    });

    test('TokenPair defaults token_type', () {
      final pair = TokenPair.fromJson({
        'access_token': 'a',
        'refresh_token': 'r',
        'expires_in': 900,
      });
      expect(pair.tokenType, 'Bearer');
      expect(pair.expiresIn, 900);
    });

    test('ShopProfile', () {
      final profile = ShopProfile.fromJson({'version': 3, 'content_md': '# Shop', 'created_at': _at});
      expect(profile.version, 3);
      expect(profile.createdAt.isUtc, isTrue);
    });

    test('MerchantUpdate sends only what is set', () {
      expect(const MerchantUpdate(agentEnabled: false).toJson(), {'agent_enabled': false});
    });
  });

  group('onboarding', () {
    test('every answer round-trips', () {
      const json = {
        'category': 'bakery',
        'area': 'Anna Nagar',
        'city': 'Chennai',
        'address': '1 Test Rd',
        'hours': '9 am to 8 pm',
        'weekly_off': 'Monday',
        'products': 'Cakes',
        'intro': 'Hi',
        'tone': 'formal',
        'emoji': false,
        'address_customers': 'sir',
        'fulfilment': 'Pickup only',
        'custom_orders': 'Two days notice',
        'cancellations': 'Before baking',
        'never_promise': 'Same-day delivery',
        'faqs': 'None',
        'upi_id': 'test@upi',
      };
      expect(OnboardingAnswers.fromJson(json).toJson(), json);
    });

    test('skipped answers stay out of the JSON', () {
      final answers = OnboardingAnswers.fromJson({'city': 'Chennai', 'tone': null});
      expect(answers.tone, isNull);
      expect(answers.toJson(), {'city': 'Chennai'});
    });

    test('copyWith keeps left-out fields and clears on null', () {
      const answers = OnboardingAnswers(city: 'Chennai', area: 'Anna Nagar', emoji: true);
      final next = answers.copyWith(area: null, hours: '9 to 5');
      expect(next.city, 'Chennai');
      expect(next.area, isNull);
      expect(next.hours, '9 to 5');
      expect(next.emoji, isTrue);
    });

    test('Onboarding with empty answers', () {
      final onboarding = Onboarding.fromJson({
        'shop_name': 'Test Bakery',
        'answers': <String, dynamic>{},
        'completed': false,
        'channels': <dynamic>[],
        'payments_ready': true,
      });
      expect(onboarding.answers.toJson(), isEmpty);
      expect(onboarding.paymentsReady, isTrue);
    });

    test('OnboardingUpdate', () {
      expect(
        const OnboardingUpdate(
          shopName: 'Test',
          answers: OnboardingAnswers(city: 'Chennai'),
          complete: true,
        ).toJson(),
        {
          'shop_name': 'Test',
          'answers': {'city': 'Chennai'},
          'complete': true,
        },
      );
    });
  });

  group('today', () {
    test('Today keeps the backend numbers apart', () {
      final today = Today.fromJson(_today());
      final row = today.stock.single;
      expect(today.businessDate, DateTime(2026, 11, 5));
      expect(today.revenueMinorByCurrency, {'INR': 180000, 'USD': 1250});
      expect(row.opening, 10);
      expect(row.restocked, 2);
      expect(row.made, 12);
      expect(row.sold, 3);
      expect(row.counterSales, 2);
      expect(row.soldTotal, 5);
      expect(row.stockMode, 'inventory');
      expect(row.shelfLifeDays, 3);
      expect(row.label, 'Plum cake (500 g)');
      expect(row.carries, isTrue);
    });

    test('StockRow from before stock_mode existed gets the defaults', () {
      final json = _stockRow()
        ..remove('stock_mode')
        ..remove('shelf_life_days');
      final row = StockRow.fromJson(json);
      expect(row.stockMode, 'daily');
      expect(row.shelfLifeDays, isNull);
      expect(row.carries, isFalse);
      expect(row.isTracked, isTrue);
    });

    test('CounterSaleResponse and RolloverResponse carry Today', () {
      final sale = CounterSaleResponse.fromJson({
        'variant_id': _uuid,
        'business_date': '2026-11-05',
        'quantity_sold': 2,
        'remaining_available': 4,
        'today': _today(),
      });
      expect(sale.remainingAvailable, 4);
      expect(sale.today.ordersPaid, 4);
      final rolled = RolloverResponse.fromJson({'rolled_count': 3, 'today': _today()});
      expect(rolled.rolledCount, 3);
    });

    test('parse-stock-text lines have no stock mode', () {
      final parsed = OpeningStock.fromJson({
        'lines': [
          {
            'product': 'Plum cake',
            'variant': null,
            'price_minor': 45000,
            'currency': 'INR',
            'quantity': 10,
          },
        ],
      });
      expect(parsed.lines.single.stockMode, isNull);
      expect(parsed.lines.single.label, 'Plum cake');
    });

    test('StockLine leaves out an unset stock mode, so the item keeps its own', () {
      const plain = StockLine(product: 'Cake', priceMinor: 100, quantity: 1);
      expect(plain.toJson(), {
        'product': 'Cake',
        'variant': null,
        'price_minor': 100,
        'currency': 'INR',
        'quantity': 1,
      });
      const kept = StockLine(
        product: 'Cake',
        priceMinor: 100,
        quantity: 1,
        stockMode: 'inventory',
        shelfLifeDays: 4,
      );
      expect(kept.toJson()['stock_mode'], 'inventory');
      expect(kept.toJson()['shelf_life_days'], 4);
    });

    test('leftovers', () {
      final found = YesterdayLeftoversResponse.fromJson({
        'business_date': '2026-11-05',
        'yesterday_date': '2026-11-04',
        'leftovers': [
          {
            'variant_id': _uuid,
            'product': 'Plum cake',
            'variant': null,
            'price_minor': 45000,
            'currency': 'INR',
            'leftover_quantity': 2,
            'stock_mode': 'daily',
            'shelf_life_days': 2,
          },
        ],
      });
      expect(found.yesterdayDate, DateTime(2026, 11, 4));
      expect(found.leftovers.single.leftoverQuantity, 2);
      expect(found.leftovers.single.keeps, isTrue);
    });

    test('rollover request', () {
      expect(
        const RolloverRequest(
          items: [RolloverItem(variantId: _uuid, rolloverQuantity: 2)],
        ).toJson(),
        {
          'items': [
            {'variant_id': _uuid, 'rollover_quantity': 2},
          ],
        },
      );
    });
  });

  group('upcoming stock', () {
    test('UpcomingDay, including an item with no variant', () {
      final day = UpcomingDay.fromJson({
        'date': '2026-11-06',
        'items': [
          {
            'product': 'Plum cake',
            'variant': null,
            'price_minor': 45000,
            'currency': 'INR',
            'available': 3,
            'variant_id': null,
            'opening': 5,
            'stock_mode': 'daily',
            'shelf_life_days': null,
          },
        ],
      });
      expect(day.date, DateTime(2026, 11, 6));
      expect(day.items.single.variantId, isNull);
      expect(day.items.single.held, 2);
    });

    test('UpcomingStock sends calendar days', () {
      final json = UpcomingStock(
        fromDate: DateTime(2026, 11, 6),
        toDate: DateTime(2026, 11, 8),
        lines: const [StockLine(product: 'Cake', priceMinor: 100, quantity: 1)],
      ).toJson();
      expect(json['from_date'], '2026-11-06');
      expect(json['to_date'], '2026-11-08');
    });
  });

  group('orders', () {
    test('Order, all fields', () {
      final order = Order.fromJson(_order());
      expect(order.number, 1046);
      expect(order.conversationId, _uuid2);
      expect(order.paidAt, isNotNull);
      expect(order.holdExpiresAt, isNull);
      expect(order.items.single.lineTotalMinor, 90000);
      expect(order.quantity, 2);
      expect(order.fulfilmentMethod, 'delivery');
      expect(order.deliveryAddress, '21 Test Street');
      expect(order.customerNote, 'Call before');
      expect(order.orderNumber, 'ORD-1046');
      expect(order.neededBy, '2026-11-06 6 pm');
      expect(order.totalAmountMinor, 90000);
    });

    test('Order, only the required fields', () {
      final order = Order.fromJson({
        'id': _uuid,
        'number': 1,
        'status': 'awaiting_payment',
        'currency': 'USD',
        'total_minor': 1250,
        'conversation_id': null,
        'created_at': _at,
        'paid_at': null,
        'hold_expires_at': null,
        'items': <dynamic>[],
      });
      expect(order.paymentStatus, 'unpaid');
      expect(order.fulfilmentStatus, 'unfulfilled');
      expect(order.channel, 'instagram');
      expect(order.fulfilmentMethod, isNull);
      expect(order.conversationId, isNull);
    });

    test('timeline, payment link, refund and invoice', () {
      final event = OrderTimelineEvent.fromJson({
        'id': _uuid,
        'order_id': _uuid2,
        'from_status': null,
        'to_status': 'awaiting_payment',
        'triggered_by': 'system',
        'comment': null,
        'created_at': _at,
      });
      expect(event.fromStatus, isNull);

      final link = PaymentLinkResponse.fromJson({
        'order_id': _uuid,
        'order_number': 7,
        'payment_method': 'upi',
        'payment_link': 'upi://pay?pa=test@upi',
        'currency': 'INR',
        'total_minor': 100,
      });
      expect(link.paymentMethod, 'upi');

      final refund = RefundResponse.fromJson({
        'order_id': _uuid,
        'refund_id': 'R-1',
        'amount_minor': 100,
        'currency': 'USD',
        'status': 'pending',
      });
      expect(refund.status, 'pending');

      final invoice = CreateInvoiceResponse.fromJson({
        'order_id': _uuid,
        'invoice_id': 'INV-1',
        'payer_view_url': 'https://example.com/i',
      });
      expect(invoice.invoiceId, 'INV-1');
    });

    test('request bodies leave out what is unset', () {
      expect(const MarkPaidRequest().toJson(), {'method': 'upi'});
      expect(const CancelOrderRequest().toJson(), isEmpty);
      expect(const RefundRequest().toJson(), {'restock': true});
      expect(const CreateInvoiceRequest().toJson(), isEmpty);
      expect(const UpdateOrderStatusRequest(status: 'ready').toJson(), {'status': 'ready'});
    });
  });

  group('questions and chats', () {
    test('Question with the window fields', () {
      final question = Question.fromJson({
        'id': _uuid,
        'conversation_id': _uuid2,
        'question': 'Eggless?',
        'status': 'answered',
        'answer': 'Yes',
        'created_at': _at,
        'answered_at': _at,
        'window_closes_at': _at,
        'window_state': 'human_agent_only',
        'answer_delivery': 'pending_window',
      });
      expect(question.windowState, 'human_agent_only');
      expect(question.answerDelivery, 'pending_window');
    });

    test('Question without the window fields', () {
      final question = Question.fromJson({
        'id': _uuid,
        'conversation_id': _uuid2,
        'question': 'Eggless?',
        'status': 'open',
        'answer': null,
        'created_at': _at,
        'answered_at': null,
      });
      expect(question.windowClosesAt, isNull);
      expect(question.answerDelivery, isNull);
    });

    test('Answer sends always', () {
      expect(const Answer(answer: 'Yes', always: true).toJson(), {'answer': 'Yes', 'always': true});
    });

    test('Conversation with no messages yet', () {
      final chat = Conversation.fromJson({
        'id': _uuid,
        'channel': 'webchat',
        'customer_handle': 'sim-tester',
        'agent_active': false,
        'agent_paused_reason': 'merchant',
        'last_message_sender': null,
        'last_message_body': null,
        'last_message_at': null,
      });
      expect(chat.agentActive, isFalse);
      expect(chat.lastMessageAt, isNull);
    });

    test('ChatMessage, draft', () {
      final message = ChatMessage.fromJson({
        'id': _uuid,
        'direction': 'outbound',
        'sender': 'agent',
        'body': 'Hello',
        'status': 'draft',
        'created_at': _at,
      });
      expect(message.isDraft, isTrue);
      expect(message.fromCustomer, isFalse);
    });

    test('MemoryFact holds any JSON value', () {
      final text = MemoryFact.fromJson({'key': 'k', 'value': 'pickup', 'updated_at': _at});
      final nested = MemoryFact.fromJson({
        'key': 'k',
        'value': {'a': 1},
        'updated_at': _at,
      });
      expect(text.value, 'pickup');
      expect(nested.value, {'a': 1});
    });
  });

  group('catalog', () {
    test('ProductDetail with variants and aliases', () {
      final product = ProductDetail.fromJson({
        'id': _uuid,
        'name': 'Plum cake',
        'title': null,
        'description': null,
        'category': 'cakes',
        'base_image_url': null,
        'stock_mode': 'daily',
        'shelf_life_days': null,
        'attributes': <String, dynamic>{},
        'is_active': true,
        'variants': [_variant()],
        'aliases': [
          {
            'id': _uuid2,
            'alias_text': 'xmas cake',
            'confidence_source': 'merchant_confirmed',
            'created_at': _at,
          },
        ],
      });
      expect(product.variants.single.costPriceMinor, 20000);
      expect(product.variants.single.attributes['eggless'], isTrue);
      expect(product.aliases.single.aliasText, 'xmas cake');
    });

    test('search, with an integer similarity', () {
      final found = CatalogSearchResponse.fromJson({
        'query': 'plum',
        'total_results': 1,
        'items': [
          {
            'product_id': _uuid,
            'product_name': 'Plum cake',
            'category': null,
            'attributes': <String, dynamic>{},
            'matched_alias': null,
            'similarity': 1,
            'variants': [_variant()],
          },
        ],
      });
      expect(found.items.single.similarity, 1.0);
    });

    test('ProductUpdate sends only what is set', () {
      expect(const ProductUpdate(category: 'cakes').toJson(), {'category': 'cakes'});
    });
  });

  group('stories', () {
    test('Story', () {
      final story = Story.fromJson({
        'story_id': '1789',
        'item_ids': ['i3f2a1b'],
        'caption': null,
        'expires_at': _at,
      });
      expect(story.itemIds, ['i3f2a1b']);
      expect(story.caption, isNull);
    });

    test('itemRefOf matches the backend: i + first six hex digits', () {
      expect(itemRefOf(_uuid), 'i3f2a1b');
    });

    test('MenuImage sends an explicit null to clear', () {
      expect(const MenuImage().toJson(), {'url': null});
    });
  });

  group('simulator', () {
    test('a chat with buttons and a turn', () {
      final chat = SimulatorChat.fromJson({
        'messages': [
          {
            'id': _uuid,
            'sender': 'agent',
            'body': 'Pickup or delivery?',
            'status': 'sent',
            'buttons': [
              {'title': 'Pickup', 'payload': 'pickup'},
            ],
            'at': _at,
          },
        ],
        'turn': {
          'id': _uuid2,
          'status': 'completed',
          'stage_before': 'browsing',
          'stage_after': 'ordering',
          'playbook': null,
          'tools': ['check_stock'],
          'model_calls': 2,
          'cost_usd': 0.004,
          'latency_ms': 1800,
        },
      });
      expect(chat.messages.single.buttons.single.payload, 'pickup');
      expect(chat.turn?.tools, ['check_stock']);
      expect(chat.turn?.costUsd, 0.004);
    });

    test('an empty chat', () {
      final chat = SimulatorChat.fromJson({'messages': <dynamic>[], 'turn': null});
      expect(chat.messages, isEmpty);
      expect(chat.turn, isNull);
    });
  });
}
