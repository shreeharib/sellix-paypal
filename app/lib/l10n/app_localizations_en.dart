// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'sellix';

  @override
  String get commonRetry => 'Try again';

  @override
  String get commonSave => 'Save';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonErrorTitle => 'Something went wrong';

  @override
  String get commonSaved => 'Saved.';

  @override
  String get signInTagline => 'Your DMs, run like a business.';

  @override
  String get signInBody =>
      'Sell in your Instagram DMs with an assistant that knows today\'s stock, takes orders and collects payment.';

  @override
  String get signInWithInstagram => 'Continue with Instagram';

  @override
  String get signInNote =>
      'Use your shop\'s Instagram professional account. Its messages will be connected to sellix.';

  @override
  String get signInCancelled => 'Sign-in was cancelled.';

  @override
  String get navToday => 'Today';

  @override
  String get navAskMe => 'Ask me';

  @override
  String get navOrders => 'Orders';

  @override
  String get navChats => 'Chats';

  @override
  String get navSettings => 'Settings';

  @override
  String get todayAgentSwitchLabel => 'Agent replies to customers';

  @override
  String get todayAgentOn => 'Replying to your DMs';

  @override
  String get todayAgentOff => 'Off: messages are saved, nobody replies';

  @override
  String get todayOpenQuestions => 'Questions for you';

  @override
  String get todayAwaitingPayment => 'Waiting for payment';

  @override
  String get todayPaidOrders => 'Paid orders';

  @override
  String get todayRevenue => 'Sales';

  @override
  String get todayStockTitle => 'Today\'s stock';

  @override
  String get todayStockEmpty => 'No stock for today yet';

  @override
  String get todayStockEmptyHint =>
      'Add what you\'ve made today so the agent can sell it.';

  @override
  String get todayUpdateStock => 'Update stock';

  @override
  String todayLeft(int count) {
    return '$count left';
  }

  @override
  String todayStockBreakdown(int opening, int held, int sold) {
    return 'Made $opening · Held $held · Sold $sold';
  }

  @override
  String get todaySoldOut => 'Sold out';

  @override
  String get stockEditorProduct => 'Product';

  @override
  String get stockEditorVariant => 'Variant (optional)';

  @override
  String get stockEditorPrice => 'Price';

  @override
  String get stockEditorCurrency => 'Currency';

  @override
  String get stockEditorQuantity => 'Quantity';

  @override
  String get stockEditorAddItem => 'Add item';

  @override
  String get stockEditorRemoveItem => 'Remove item';

  @override
  String get stockEditorSave => 'Save stock';

  @override
  String get stockEditorInvalid =>
      'Fill in a product, a price and a quantity for every item.';

  @override
  String get askMeOpen => 'Open';

  @override
  String get askMeAnswered => 'Answered';

  @override
  String get askMeEmpty => 'No questions right now';

  @override
  String get askMeEmptyHint => 'When the agent isn\'t sure, it asks you here.';

  @override
  String get askMeAnswerHint =>
      'Your answer. The agent passes it on to the customer.';

  @override
  String get askMeSendAnswer => 'Send answer';

  @override
  String get askMeDismiss => 'Dismiss';

  @override
  String get askMeYourAnswer => 'Your answer';

  @override
  String get askMeAnswerSent => 'Sent. The agent will reply to the customer.';

  @override
  String get ordersFilterAll => 'All';

  @override
  String get ordersEmpty => 'No orders yet';

  @override
  String get ordersEmptyHint =>
      'Orders the agent takes in your DMs appear here.';

  @override
  String ordersNumber(int number) {
    return 'Order #$number';
  }

  @override
  String get ordersStatusAwaiting => 'Waiting for payment';

  @override
  String get ordersStatusPaid => 'Paid';

  @override
  String get ordersStatusExpired => 'Expired';

  @override
  String get ordersStatusCancelled => 'Cancelled';

  @override
  String get ordersStatusCompleted => 'Completed';

  @override
  String get ordersStatusRefunded => 'Refunded';

  @override
  String get ordersPickup => 'Pickup';

  @override
  String get ordersDelivery => 'Delivery';

  @override
  String ordersNeededBy(String when) {
    return 'Needed: $when';
  }

  @override
  String ordersHeldUntil(String time) {
    return 'Held until $time';
  }

  @override
  String get chatsEmpty => 'No chats yet';

  @override
  String get chatsEmptyHint =>
      'When customers message your shop on Instagram, their chats appear here.';

  @override
  String get chatsAgentPaused => 'Agent paused';

  @override
  String get chatsAgentInThisChat => 'Agent replies in this chat';

  @override
  String get chatsAgentInThisChatOff => 'You\'re handling this chat';

  @override
  String get chatsSenderAgent => 'Agent';

  @override
  String get chatsSenderYou => 'You';

  @override
  String get chatsNoMessages => 'No messages';

  @override
  String get chatsNotDelivered => 'Not delivered';

  @override
  String get settingsShopName => 'Shop name';

  @override
  String get settingsAgentHint =>
      'Turn off to stop all automatic replies. Messages are still saved.';

  @override
  String get settingsProfile => 'Shop profile';

  @override
  String get settingsProfileHint =>
      'What the agent knows about your shop: hours, pickup and delivery, policies, common questions.';

  @override
  String get settingsProfileSaved => 'Shop profile saved.';

  @override
  String get settingsChannels => 'Connected accounts';

  @override
  String settingsInstagram(String username) {
    return 'Instagram · @$username';
  }

  @override
  String get settingsSignOut => 'Sign out';

  @override
  String onboardingStep(int step, int total) {
    return 'Step $step of $total';
  }

  @override
  String get onboardingFinishLater => 'Finish later';

  @override
  String get onboardingBack => 'Back';

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingFinish => 'Finish';

  @override
  String get onboardingNameRequired => 'Enter your shop\'s name.';

  @override
  String get onboardingConnectedTitle => 'Your Instagram is connected';

  @override
  String get onboardingConnectedBody =>
      'sellix now receives your shop\'s Instagram DMs. Answer a few questions about your shop so the agent knows how to reply. You can skip any step and finish it later in Settings.';

  @override
  String get onboardingReceivingMessages => 'Receiving messages';

  @override
  String get onboardingNotConnectedTitle => 'Instagram isn\'t connected';

  @override
  String get onboardingNotConnectedBody =>
      'sellix can\'t receive your DMs yet. Sign out and continue with your shop\'s Instagram professional account. You can still set up your shop now.';

  @override
  String get onboardingShopTitle => 'Your shop';

  @override
  String get onboardingShopBody => 'The basics customers ask about.';

  @override
  String get onboardingCategory => 'What kind of shop';

  @override
  String get onboardingCategoryHint => 'Home bakery, clothing…';

  @override
  String get onboardingArea => 'Area';

  @override
  String get onboardingCity => 'City';

  @override
  String get onboardingAddress => 'Address for pickup';

  @override
  String get onboardingHours => 'Working days and hours';

  @override
  String get onboardingHoursHint => 'Tue–Sun, 9 am – 8 pm';

  @override
  String get onboardingWeeklyOff => 'Weekly off';

  @override
  String get onboardingWeeklyOffHint => 'Mondays';

  @override
  String get onboardingProductsTitle => 'What you sell';

  @override
  String get onboardingProductsBody =>
      'In plain words. No prices or quantities: you add those with each morning\'s stock.';

  @override
  String get onboardingProducts => 'Products';

  @override
  String get onboardingProductsHint =>
      'Cookies, brownies, custom birthday cakes, cupcakes';

  @override
  String get onboardingPersonaTitle => 'How the agent talks';

  @override
  String get onboardingPersonaBody =>
      'How your assistant sounds when it replies to customers.';

  @override
  String get onboardingIntro => 'How it introduces itself';

  @override
  String get onboardingIntroHint => 'Hi, I\'m Sweet Crumbs\' assistant';

  @override
  String get onboardingTone => 'Tone';

  @override
  String get onboardingToneFriendly => 'Friendly';

  @override
  String get onboardingToneFormal => 'Formal';

  @override
  String get onboardingEmoji => 'Use emoji';

  @override
  String get onboardingAddressCustomers => 'How to address customers';

  @override
  String get onboardingAddressCustomersHint =>
      'Sir/madam until they share a name';

  @override
  String get onboardingPoliciesTitle => 'Policies and common questions';

  @override
  String get onboardingPoliciesBody =>
      'The agent follows these and asks you about anything else.';

  @override
  String get onboardingFulfilment => 'Pickup and delivery';

  @override
  String get onboardingFulfilmentHint =>
      'Pickup from Anna Nagar, or we deliver nearby';

  @override
  String get onboardingCustomOrders => 'Custom orders';

  @override
  String get onboardingCustomOrdersHint => 'Yes, 2 days\' notice, 50% advance';

  @override
  String get onboardingCancellations => 'Cancellations and refunds';

  @override
  String get onboardingNeverPromise => 'Things the agent must never promise';

  @override
  String get onboardingNeverPromiseHint =>
      'Same-day custom cakes, delivery times';

  @override
  String get onboardingFaqs => 'Common questions and answers';

  @override
  String get onboardingFaqsHint => 'Eggless? Yes, on request.';

  @override
  String get onboardingPaymentsTitle => 'Payments';

  @override
  String get onboardingPaymentsBody =>
      'How customers pay for orders the agent takes.';

  @override
  String get onboardingPayPal => 'PayPal';

  @override
  String get onboardingPaymentsReady =>
      'Ready. Customers get a payment link, and the order is marked paid when PayPal confirms it.';

  @override
  String get onboardingPaymentsNotReady =>
      'Not set up yet. Until it is, orders wait for you to confirm the payment.';
}
