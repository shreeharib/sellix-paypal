import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ta.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ta'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'sellix'**
  String get appTitle;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get commonRetry;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get commonErrorTitle;

  /// No description provided for @commonSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved.'**
  String get commonSaved;

  /// No description provided for @signInTagline.
  ///
  /// In en, this message translates to:
  /// **'Your DMs, run like a business.'**
  String get signInTagline;

  /// No description provided for @signInBody.
  ///
  /// In en, this message translates to:
  /// **'Sell in your Instagram DMs with an assistant that knows today\'s stock, takes orders and collects payment.'**
  String get signInBody;

  /// No description provided for @signInWithInstagram.
  ///
  /// In en, this message translates to:
  /// **'Continue with Instagram'**
  String get signInWithInstagram;

  /// No description provided for @signInNote.
  ///
  /// In en, this message translates to:
  /// **'Use your shop\'s Instagram professional account. Its messages will be connected to sellix.'**
  String get signInNote;

  /// No description provided for @signInCancelled.
  ///
  /// In en, this message translates to:
  /// **'Sign-in was cancelled.'**
  String get signInCancelled;

  /// No description provided for @navToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get navToday;

  /// No description provided for @navAskMe.
  ///
  /// In en, this message translates to:
  /// **'Ask me'**
  String get navAskMe;

  /// No description provided for @navOrders.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get navOrders;

  /// No description provided for @navChats.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get navChats;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @todayAgentSwitchLabel.
  ///
  /// In en, this message translates to:
  /// **'Agent replies to customers'**
  String get todayAgentSwitchLabel;

  /// No description provided for @todayAgentOn.
  ///
  /// In en, this message translates to:
  /// **'Replying to your DMs'**
  String get todayAgentOn;

  /// No description provided for @todayAgentOff.
  ///
  /// In en, this message translates to:
  /// **'Off: messages are saved, nobody replies'**
  String get todayAgentOff;

  /// No description provided for @todayOpenQuestions.
  ///
  /// In en, this message translates to:
  /// **'Questions for you'**
  String get todayOpenQuestions;

  /// No description provided for @todayAwaitingPayment.
  ///
  /// In en, this message translates to:
  /// **'Waiting for payment'**
  String get todayAwaitingPayment;

  /// No description provided for @todayPaidOrders.
  ///
  /// In en, this message translates to:
  /// **'Paid orders'**
  String get todayPaidOrders;

  /// No description provided for @todayRevenue.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get todayRevenue;

  /// No description provided for @todayStockTitle.
  ///
  /// In en, this message translates to:
  /// **'Today\'s stock'**
  String get todayStockTitle;

  /// No description provided for @todayStockEmpty.
  ///
  /// In en, this message translates to:
  /// **'No stock for today yet'**
  String get todayStockEmpty;

  /// No description provided for @todayStockEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Add what you\'ve made today so the agent can sell it.'**
  String get todayStockEmptyHint;

  /// No description provided for @todayUpdateStock.
  ///
  /// In en, this message translates to:
  /// **'Update stock'**
  String get todayUpdateStock;

  /// No description provided for @todayLeft.
  ///
  /// In en, this message translates to:
  /// **'{count} left'**
  String todayLeft(int count);

  /// No description provided for @todayStockBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Made {opening} · Held {held} · Sold {sold}'**
  String todayStockBreakdown(int opening, int held, int sold);

  /// No description provided for @todaySoldOut.
  ///
  /// In en, this message translates to:
  /// **'Sold out'**
  String get todaySoldOut;

  /// No description provided for @stockEditorProduct.
  ///
  /// In en, this message translates to:
  /// **'Product'**
  String get stockEditorProduct;

  /// No description provided for @stockEditorVariant.
  ///
  /// In en, this message translates to:
  /// **'Variant (optional)'**
  String get stockEditorVariant;

  /// No description provided for @stockEditorPrice.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get stockEditorPrice;

  /// No description provided for @stockEditorCurrency.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get stockEditorCurrency;

  /// No description provided for @stockEditorQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get stockEditorQuantity;

  /// No description provided for @stockEditorAddItem.
  ///
  /// In en, this message translates to:
  /// **'Add item'**
  String get stockEditorAddItem;

  /// No description provided for @stockEditorRemoveItem.
  ///
  /// In en, this message translates to:
  /// **'Remove item'**
  String get stockEditorRemoveItem;

  /// No description provided for @stockEditorSave.
  ///
  /// In en, this message translates to:
  /// **'Save stock'**
  String get stockEditorSave;

  /// No description provided for @stockEditorInvalid.
  ///
  /// In en, this message translates to:
  /// **'Fill in a product, a price and a quantity for every item.'**
  String get stockEditorInvalid;

  /// No description provided for @askMeOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get askMeOpen;

  /// No description provided for @askMeAnswered.
  ///
  /// In en, this message translates to:
  /// **'Answered'**
  String get askMeAnswered;

  /// No description provided for @askMeEmpty.
  ///
  /// In en, this message translates to:
  /// **'No questions right now'**
  String get askMeEmpty;

  /// No description provided for @askMeEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'When the agent isn\'t sure, it asks you here.'**
  String get askMeEmptyHint;

  /// No description provided for @askMeAnswerHint.
  ///
  /// In en, this message translates to:
  /// **'Your answer. The agent passes it on to the customer.'**
  String get askMeAnswerHint;

  /// No description provided for @askMeSendAnswer.
  ///
  /// In en, this message translates to:
  /// **'Send answer'**
  String get askMeSendAnswer;

  /// No description provided for @askMeDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get askMeDismiss;

  /// No description provided for @askMeYourAnswer.
  ///
  /// In en, this message translates to:
  /// **'Your answer'**
  String get askMeYourAnswer;

  /// No description provided for @askMeAnswerSent.
  ///
  /// In en, this message translates to:
  /// **'Sent. The agent will reply to the customer.'**
  String get askMeAnswerSent;

  /// No description provided for @ordersFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get ordersFilterAll;

  /// No description provided for @ordersEmpty.
  ///
  /// In en, this message translates to:
  /// **'No orders yet'**
  String get ordersEmpty;

  /// No description provided for @ordersEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Orders the agent takes in your DMs appear here.'**
  String get ordersEmptyHint;

  /// No description provided for @ordersNumber.
  ///
  /// In en, this message translates to:
  /// **'Order #{number}'**
  String ordersNumber(int number);

  /// No description provided for @ordersStatusAwaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for payment'**
  String get ordersStatusAwaiting;

  /// No description provided for @ordersStatusPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get ordersStatusPaid;

  /// No description provided for @ordersStatusExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get ordersStatusExpired;

  /// No description provided for @ordersStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get ordersStatusCancelled;

  /// No description provided for @ordersStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get ordersStatusCompleted;

  /// No description provided for @ordersStatusRefunded.
  ///
  /// In en, this message translates to:
  /// **'Refunded'**
  String get ordersStatusRefunded;

  /// No description provided for @ordersPickup.
  ///
  /// In en, this message translates to:
  /// **'Pickup'**
  String get ordersPickup;

  /// No description provided for @ordersDelivery.
  ///
  /// In en, this message translates to:
  /// **'Delivery'**
  String get ordersDelivery;

  /// No description provided for @ordersNeededBy.
  ///
  /// In en, this message translates to:
  /// **'Needed: {when}'**
  String ordersNeededBy(String when);

  /// No description provided for @ordersHeldUntil.
  ///
  /// In en, this message translates to:
  /// **'Held until {time}'**
  String ordersHeldUntil(String time);

  /// No description provided for @chatsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No chats yet'**
  String get chatsEmpty;

  /// No description provided for @chatsEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'When customers message your shop on Instagram, their chats appear here.'**
  String get chatsEmptyHint;

  /// No description provided for @chatsAgentPaused.
  ///
  /// In en, this message translates to:
  /// **'Agent paused'**
  String get chatsAgentPaused;

  /// No description provided for @chatsAgentInThisChat.
  ///
  /// In en, this message translates to:
  /// **'Agent replies in this chat'**
  String get chatsAgentInThisChat;

  /// No description provided for @chatsAgentInThisChatOff.
  ///
  /// In en, this message translates to:
  /// **'You\'re handling this chat'**
  String get chatsAgentInThisChatOff;

  /// No description provided for @chatsSenderAgent.
  ///
  /// In en, this message translates to:
  /// **'Agent'**
  String get chatsSenderAgent;

  /// No description provided for @chatsSenderYou.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get chatsSenderYou;

  /// No description provided for @chatsNoMessages.
  ///
  /// In en, this message translates to:
  /// **'No messages'**
  String get chatsNoMessages;

  /// No description provided for @chatsNotDelivered.
  ///
  /// In en, this message translates to:
  /// **'Not delivered'**
  String get chatsNotDelivered;

  /// No description provided for @settingsShopName.
  ///
  /// In en, this message translates to:
  /// **'Shop name'**
  String get settingsShopName;

  /// No description provided for @settingsAgentHint.
  ///
  /// In en, this message translates to:
  /// **'Turn off to stop all automatic replies. Messages are still saved.'**
  String get settingsAgentHint;

  /// No description provided for @settingsProfile.
  ///
  /// In en, this message translates to:
  /// **'Shop profile'**
  String get settingsProfile;

  /// No description provided for @settingsProfileHint.
  ///
  /// In en, this message translates to:
  /// **'What the agent knows about your shop: hours, pickup and delivery, policies, common questions.'**
  String get settingsProfileHint;

  /// No description provided for @settingsProfileSaved.
  ///
  /// In en, this message translates to:
  /// **'Shop profile saved.'**
  String get settingsProfileSaved;

  /// No description provided for @settingsChannels.
  ///
  /// In en, this message translates to:
  /// **'Connected accounts'**
  String get settingsChannels;

  /// No description provided for @settingsInstagram.
  ///
  /// In en, this message translates to:
  /// **'Instagram · @{username}'**
  String settingsInstagram(String username);

  /// No description provided for @settingsSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get settingsSignOut;

  /// No description provided for @onboardingStep.
  ///
  /// In en, this message translates to:
  /// **'Step {step} of {total}'**
  String onboardingStep(int step, int total);

  /// No description provided for @onboardingFinishLater.
  ///
  /// In en, this message translates to:
  /// **'Finish later'**
  String get onboardingFinishLater;

  /// No description provided for @onboardingBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get onboardingBack;

  /// No description provided for @onboardingSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboardingSkip;

  /// No description provided for @onboardingNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get onboardingNext;

  /// No description provided for @onboardingFinish.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get onboardingFinish;

  /// No description provided for @onboardingNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter your shop\'s name.'**
  String get onboardingNameRequired;

  /// No description provided for @onboardingConnectedTitle.
  ///
  /// In en, this message translates to:
  /// **'Your Instagram is connected'**
  String get onboardingConnectedTitle;

  /// No description provided for @onboardingConnectedBody.
  ///
  /// In en, this message translates to:
  /// **'sellix now receives your shop\'s Instagram DMs. Answer a few questions about your shop so the agent knows how to reply. You can skip any step and finish it later in Settings.'**
  String get onboardingConnectedBody;

  /// No description provided for @onboardingReceivingMessages.
  ///
  /// In en, this message translates to:
  /// **'Receiving messages'**
  String get onboardingReceivingMessages;

  /// No description provided for @onboardingNotConnectedTitle.
  ///
  /// In en, this message translates to:
  /// **'Instagram isn\'t connected'**
  String get onboardingNotConnectedTitle;

  /// No description provided for @onboardingNotConnectedBody.
  ///
  /// In en, this message translates to:
  /// **'sellix can\'t receive your DMs yet. Sign out and continue with your shop\'s Instagram professional account. You can still set up your shop now.'**
  String get onboardingNotConnectedBody;

  /// No description provided for @onboardingShopTitle.
  ///
  /// In en, this message translates to:
  /// **'Your shop'**
  String get onboardingShopTitle;

  /// No description provided for @onboardingShopBody.
  ///
  /// In en, this message translates to:
  /// **'The basics customers ask about.'**
  String get onboardingShopBody;

  /// No description provided for @onboardingCategory.
  ///
  /// In en, this message translates to:
  /// **'What kind of shop'**
  String get onboardingCategory;

  /// No description provided for @onboardingCategoryHint.
  ///
  /// In en, this message translates to:
  /// **'Home bakery, clothing…'**
  String get onboardingCategoryHint;

  /// No description provided for @onboardingArea.
  ///
  /// In en, this message translates to:
  /// **'Area'**
  String get onboardingArea;

  /// No description provided for @onboardingCity.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get onboardingCity;

  /// No description provided for @onboardingAddress.
  ///
  /// In en, this message translates to:
  /// **'Address for pickup'**
  String get onboardingAddress;

  /// No description provided for @onboardingHours.
  ///
  /// In en, this message translates to:
  /// **'Working days and hours'**
  String get onboardingHours;

  /// No description provided for @onboardingHoursHint.
  ///
  /// In en, this message translates to:
  /// **'Tue–Sun, 9 am – 8 pm'**
  String get onboardingHoursHint;

  /// No description provided for @onboardingWeeklyOff.
  ///
  /// In en, this message translates to:
  /// **'Weekly off'**
  String get onboardingWeeklyOff;

  /// No description provided for @onboardingWeeklyOffHint.
  ///
  /// In en, this message translates to:
  /// **'Mondays'**
  String get onboardingWeeklyOffHint;

  /// No description provided for @onboardingProductsTitle.
  ///
  /// In en, this message translates to:
  /// **'What you sell'**
  String get onboardingProductsTitle;

  /// No description provided for @onboardingProductsBody.
  ///
  /// In en, this message translates to:
  /// **'In plain words. No prices or quantities: you add those with each morning\'s stock.'**
  String get onboardingProductsBody;

  /// No description provided for @onboardingProducts.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get onboardingProducts;

  /// No description provided for @onboardingProductsHint.
  ///
  /// In en, this message translates to:
  /// **'Cookies, brownies, custom birthday cakes, cupcakes'**
  String get onboardingProductsHint;

  /// No description provided for @onboardingPersonaTitle.
  ///
  /// In en, this message translates to:
  /// **'How the agent talks'**
  String get onboardingPersonaTitle;

  /// No description provided for @onboardingPersonaBody.
  ///
  /// In en, this message translates to:
  /// **'How your assistant sounds when it replies to customers.'**
  String get onboardingPersonaBody;

  /// No description provided for @onboardingIntro.
  ///
  /// In en, this message translates to:
  /// **'How it introduces itself'**
  String get onboardingIntro;

  /// No description provided for @onboardingIntroHint.
  ///
  /// In en, this message translates to:
  /// **'Hi, I\'m Sweet Crumbs\' assistant'**
  String get onboardingIntroHint;

  /// No description provided for @onboardingTone.
  ///
  /// In en, this message translates to:
  /// **'Tone'**
  String get onboardingTone;

  /// No description provided for @onboardingToneFriendly.
  ///
  /// In en, this message translates to:
  /// **'Friendly'**
  String get onboardingToneFriendly;

  /// No description provided for @onboardingToneFormal.
  ///
  /// In en, this message translates to:
  /// **'Formal'**
  String get onboardingToneFormal;

  /// No description provided for @onboardingEmoji.
  ///
  /// In en, this message translates to:
  /// **'Use emoji'**
  String get onboardingEmoji;

  /// No description provided for @onboardingAddressCustomers.
  ///
  /// In en, this message translates to:
  /// **'How to address customers'**
  String get onboardingAddressCustomers;

  /// No description provided for @onboardingAddressCustomersHint.
  ///
  /// In en, this message translates to:
  /// **'Sir/madam until they share a name'**
  String get onboardingAddressCustomersHint;

  /// No description provided for @onboardingPoliciesTitle.
  ///
  /// In en, this message translates to:
  /// **'Policies and common questions'**
  String get onboardingPoliciesTitle;

  /// No description provided for @onboardingPoliciesBody.
  ///
  /// In en, this message translates to:
  /// **'The agent follows these and asks you about anything else.'**
  String get onboardingPoliciesBody;

  /// No description provided for @onboardingFulfilment.
  ///
  /// In en, this message translates to:
  /// **'Pickup and delivery'**
  String get onboardingFulfilment;

  /// No description provided for @onboardingFulfilmentHint.
  ///
  /// In en, this message translates to:
  /// **'Pickup from Anna Nagar, or we deliver nearby'**
  String get onboardingFulfilmentHint;

  /// No description provided for @onboardingCustomOrders.
  ///
  /// In en, this message translates to:
  /// **'Custom orders'**
  String get onboardingCustomOrders;

  /// No description provided for @onboardingCustomOrdersHint.
  ///
  /// In en, this message translates to:
  /// **'Yes, 2 days\' notice, 50% advance'**
  String get onboardingCustomOrdersHint;

  /// No description provided for @onboardingCancellations.
  ///
  /// In en, this message translates to:
  /// **'Cancellations and refunds'**
  String get onboardingCancellations;

  /// No description provided for @onboardingNeverPromise.
  ///
  /// In en, this message translates to:
  /// **'Things the agent must never promise'**
  String get onboardingNeverPromise;

  /// No description provided for @onboardingNeverPromiseHint.
  ///
  /// In en, this message translates to:
  /// **'Same-day custom cakes, delivery times'**
  String get onboardingNeverPromiseHint;

  /// No description provided for @onboardingFaqs.
  ///
  /// In en, this message translates to:
  /// **'Common questions and answers'**
  String get onboardingFaqs;

  /// No description provided for @onboardingFaqsHint.
  ///
  /// In en, this message translates to:
  /// **'Eggless? Yes, on request.'**
  String get onboardingFaqsHint;

  /// No description provided for @onboardingPaymentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get onboardingPaymentsTitle;

  /// No description provided for @onboardingPaymentsBody.
  ///
  /// In en, this message translates to:
  /// **'How customers pay for orders the agent takes.'**
  String get onboardingPaymentsBody;

  /// No description provided for @onboardingPayPal.
  ///
  /// In en, this message translates to:
  /// **'PayPal'**
  String get onboardingPayPal;

  /// No description provided for @onboardingPaymentsReady.
  ///
  /// In en, this message translates to:
  /// **'Ready. Customers get a payment link, and the order is marked paid when PayPal confirms it.'**
  String get onboardingPaymentsReady;

  /// No description provided for @onboardingPaymentsNotReady.
  ///
  /// In en, this message translates to:
  /// **'Not set up yet. Until it is, orders wait for you to confirm the payment.'**
  String get onboardingPaymentsNotReady;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ta'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ta':
      return AppLocalizationsTa();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
