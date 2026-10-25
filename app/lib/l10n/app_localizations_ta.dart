// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Tamil (`ta`).
class AppLocalizationsTa extends AppLocalizations {
  AppLocalizationsTa([String locale = 'ta']) : super(locale);

  @override
  String get appTitle => 'sellix';

  @override
  String get commonRetry => 'மீண்டும் முயற்சிக்கவும்';

  @override
  String get commonSave => 'சேமி';

  @override
  String get commonCancel => 'ரத்து';

  @override
  String get commonErrorTitle => 'ஏதோ தவறு நடந்தது';

  @override
  String get commonSaved => 'சேமிக்கப்பட்டது.';

  @override
  String get signInTagline => 'உங்கள் DM-களை ஒரு வணிகம் போல நடத்துங்கள்.';

  @override
  String get signInBody =>
      'இன்றைய இருப்பை அறிந்து, ஆர்டர்களை எடுத்து, பணம் வசூலிக்கும் உதவியாளருடன் உங்கள் Instagram DM-களில் விற்பனை செய்யுங்கள்.';

  @override
  String get signInWithInstagram => 'Instagram மூலம் தொடரவும்';

  @override
  String get signInNote =>
      'உங்கள் கடையின் Instagram professional கணக்கைப் பயன்படுத்துங்கள். அதன் செய்திகள் sellix-உடன் இணைக்கப்படும்.';

  @override
  String get signInCancelled => 'உள்நுழைவு ரத்து செய்யப்பட்டது.';

  @override
  String get navToday => 'இன்று';

  @override
  String get navAskMe => 'கேள்விகள்';

  @override
  String get navOrders => 'ஆர்டர்கள்';

  @override
  String get navChats => 'உரையாடல்கள்';

  @override
  String get navSettings => 'அமைப்புகள்';

  @override
  String get todayAgentSwitchLabel =>
      'உதவியாளர் வாடிக்கையாளர்களுக்குப் பதிலளிக்கும்';

  @override
  String get todayAgentOn => 'உங்கள் DM-களுக்குப் பதிலளிக்கிறது';

  @override
  String get todayAgentOff =>
      'நிறுத்தப்பட்டுள்ளது: செய்திகள் சேமிக்கப்படும், பதில் இல்லை';

  @override
  String get todayOpenQuestions => 'உங்களுக்கான கேள்விகள்';

  @override
  String get todayAwaitingPayment => 'பணம் காத்திருக்கிறது';

  @override
  String get todayPaidOrders => 'பணம் செலுத்திய ஆர்டர்கள்';

  @override
  String get todayRevenue => 'விற்பனை';

  @override
  String get todayStockTitle => 'இன்றைய இருப்பு';

  @override
  String get todayStockEmpty => 'இன்றைக்கு இன்னும் இருப்பு இல்லை';

  @override
  String get todayStockEmptyHint =>
      'உதவியாளர் விற்க, இன்று நீங்கள் செய்தவற்றைச் சேர்க்கவும்.';

  @override
  String get todayUpdateStock => 'இருப்பைப் புதுப்பி';

  @override
  String todayLeft(int count) {
    return '$count மீதம்';
  }

  @override
  String todayStockBreakdown(int opening, int held, int sold) {
    return 'செய்தது $opening · ஒதுக்கியது $held · விற்றது $sold';
  }

  @override
  String get todaySoldOut => 'தீர்ந்துவிட்டது';

  @override
  String get stockEditorProduct => 'பொருள்';

  @override
  String get stockEditorVariant => 'வகை (விருப்பம்)';

  @override
  String get stockEditorPrice => 'விலை';

  @override
  String get stockEditorCurrency => 'நாணயம்';

  @override
  String get stockEditorQuantity => 'அளவு';

  @override
  String get stockEditorAddItem => 'பொருள் சேர்';

  @override
  String get stockEditorRemoveItem => 'பொருளை நீக்கு';

  @override
  String get stockEditorSave => 'இருப்பைச் சேமி';

  @override
  String get stockEditorInvalid =>
      'ஒவ்வொரு பொருளுக்கும் பெயர், விலை, அளவு நிரப்பவும்.';

  @override
  String get askMeOpen => 'திறந்தவை';

  @override
  String get askMeAnswered => 'பதிலளித்தவை';

  @override
  String get askMeEmpty => 'இப்போது கேள்விகள் இல்லை';

  @override
  String get askMeEmptyHint =>
      'உதவியாளருக்குச் சந்தேகம் வந்தால், இங்கே உங்களிடம் கேட்கும்.';

  @override
  String get askMeAnswerHint =>
      'உங்கள் பதில். உதவியாளர் அதை வாடிக்கையாளரிடம் தெரிவிக்கும்.';

  @override
  String get askMeSendAnswer => 'பதில் அனுப்பு';

  @override
  String get askMeDismiss => 'நிராகரி';

  @override
  String get askMeYourAnswer => 'உங்கள் பதில்';

  @override
  String get askMeAnswerSent =>
      'அனுப்பப்பட்டது. உதவியாளர் வாடிக்கையாளருக்குப் பதிலளிக்கும்.';

  @override
  String get ordersFilterAll => 'அனைத்தும்';

  @override
  String get ordersEmpty => 'இன்னும் ஆர்டர்கள் இல்லை';

  @override
  String get ordersEmptyHint =>
      'உங்கள் DM-களில் உதவியாளர் எடுக்கும் ஆர்டர்கள் இங்கே தோன்றும்.';

  @override
  String ordersNumber(int number) {
    return 'ஆர்டர் #$number';
  }

  @override
  String get ordersStatusAwaiting => 'பணம் காத்திருக்கிறது';

  @override
  String get ordersStatusPaid => 'பணம் செலுத்தப்பட்டது';

  @override
  String get ordersStatusExpired => 'காலாவதியானது';

  @override
  String get ordersStatusCancelled => 'ரத்து செய்யப்பட்டது';

  @override
  String get ordersStatusCompleted => 'முடிந்தது';

  @override
  String get ordersStatusRefunded => 'பணம் திருப்பித் தரப்பட்டது';

  @override
  String get ordersPickup => 'நேரில் பெறுதல்';

  @override
  String get ordersDelivery => 'டெலிவரி';

  @override
  String ordersNeededBy(String when) {
    return 'தேவை: $when';
  }

  @override
  String ordersHeldUntil(String time) {
    return '$time வரை ஒதுக்கப்பட்டுள்ளது';
  }

  @override
  String get chatsEmpty => 'இன்னும் உரையாடல்கள் இல்லை';

  @override
  String get chatsEmptyHint =>
      'வாடிக்கையாளர்கள் Instagram-இல் உங்கள் கடைக்குச் செய்தி அனுப்பும்போது, அவை இங்கே தோன்றும்.';

  @override
  String get chatsAgentPaused => 'உதவியாளர் இடைநிறுத்தம்';

  @override
  String get chatsAgentInThisChat => 'இந்த உரையாடலில் உதவியாளர் பதிலளிக்கும்';

  @override
  String get chatsAgentInThisChatOff => 'இந்த உரையாடலை நீங்கள் கவனிக்கிறீர்கள்';

  @override
  String get chatsSenderAgent => 'உதவியாளர்';

  @override
  String get chatsSenderYou => 'நீங்கள்';

  @override
  String get chatsNoMessages => 'செய்திகள் இல்லை';

  @override
  String get chatsNotDelivered => 'அனுப்பப்படவில்லை';

  @override
  String get settingsShopName => 'கடையின் பெயர்';

  @override
  String get settingsAgentHint =>
      'எல்லா தானியங்கி பதில்களையும் நிறுத்த அணைக்கவும். செய்திகள் தொடர்ந்து சேமிக்கப்படும்.';

  @override
  String get settingsProfile => 'கடை விவரம்';

  @override
  String get settingsProfileHint =>
      'உங்கள் கடையைப் பற்றி உதவியாளருக்குத் தெரிந்தவை: நேரம், பெறுதல் மற்றும் டெலிவரி, கொள்கைகள், பொதுவான கேள்விகள்.';

  @override
  String get settingsProfileSaved => 'கடை விவரம் சேமிக்கப்பட்டது.';

  @override
  String get settingsChannels => 'இணைக்கப்பட்ட கணக்குகள்';

  @override
  String settingsInstagram(String username) {
    return 'Instagram · @$username';
  }

  @override
  String get settingsSignOut => 'வெளியேறு';

  @override
  String onboardingStep(int step, int total) {
    return 'படி $step / $total';
  }

  @override
  String get onboardingFinishLater => 'பிறகு முடிக்கவும்';

  @override
  String get onboardingBack => 'பின்செல்';

  @override
  String get onboardingSkip => 'தவிர்';

  @override
  String get onboardingNext => 'அடுத்து';

  @override
  String get onboardingFinish => 'முடி';

  @override
  String get onboardingNameRequired => 'உங்கள் கடையின் பெயரை உள்ளிடவும்.';

  @override
  String get onboardingConnectedTitle => 'உங்கள் Instagram இணைக்கப்பட்டது';

  @override
  String get onboardingConnectedBody =>
      'இனி உங்கள் கடையின் Instagram DM-கள் sellix-க்கு வரும். ஏஜென்ட் எப்படி பதில் சொல்ல வேண்டும் என்று தெரிந்துகொள்ள, உங்கள் கடை பற்றி சில கேள்விகளுக்குப் பதில் சொல்லுங்கள். எந்தப் படியையும் தவிர்த்து, பிறகு அமைப்புகளில் முடிக்கலாம்.';

  @override
  String get onboardingReceivingMessages => 'செய்திகள் வருகின்றன';

  @override
  String get onboardingNotConnectedTitle => 'Instagram இணைக்கப்படவில்லை';

  @override
  String get onboardingNotConnectedBody =>
      'sellix-க்கு இன்னும் உங்கள் DM-கள் வரவில்லை. வெளியேறி, உங்கள் கடையின் Instagram professional கணக்குடன் மீண்டும் தொடருங்கள். கடை விவரங்களை இப்போதே அமைக்கலாம்.';

  @override
  String get onboardingShopTitle => 'உங்கள் கடை';

  @override
  String get onboardingShopBody =>
      'வாடிக்கையாளர்கள் கேட்கும் அடிப்படை விவரங்கள்.';

  @override
  String get onboardingCategory => 'என்ன வகைக் கடை';

  @override
  String get onboardingCategoryHint => 'வீட்டு பேக்கரி, ஆடைகள்…';

  @override
  String get onboardingArea => 'பகுதி';

  @override
  String get onboardingCity => 'நகரம்';

  @override
  String get onboardingAddress => 'பிக்கப் முகவரி';

  @override
  String get onboardingHours => 'வேலை நாட்களும் நேரமும்';

  @override
  String get onboardingHoursHint => 'செவ்–ஞாயிறு, காலை 9 – இரவு 8';

  @override
  String get onboardingWeeklyOff => 'வார விடுமுறை';

  @override
  String get onboardingWeeklyOffHint => 'திங்கள்';

  @override
  String get onboardingProductsTitle => 'நீங்கள் விற்பவை';

  @override
  String get onboardingProductsBody =>
      'எளிய வார்த்தைகளில். விலையும் அளவும் வேண்டாம்: அவற்றை ஒவ்வொரு காலை ஸ்டாக்குடன் சேர்ப்பீர்கள்.';

  @override
  String get onboardingProducts => 'பொருட்கள்';

  @override
  String get onboardingProductsHint =>
      'குக்கீஸ், பிரவுனி, பிறந்தநாள் கேக், கப்கேக்';

  @override
  String get onboardingPersonaTitle => 'ஏஜென்ட் பேசும் விதம்';

  @override
  String get onboardingPersonaBody =>
      'வாடிக்கையாளர்களுக்குப் பதில் சொல்லும்போது உங்கள் உதவியாளர் எப்படிப் பேச வேண்டும்.';

  @override
  String get onboardingIntro => 'தன்னை எப்படி அறிமுகம் செய்யும்';

  @override
  String get onboardingIntroHint => 'வணக்கம், நான் Sweet Crumbs உதவியாளர்';

  @override
  String get onboardingTone => 'தொனி';

  @override
  String get onboardingToneFriendly => 'நட்பான';

  @override
  String get onboardingToneFormal => 'முறையான';

  @override
  String get onboardingEmoji => 'எமோஜி பயன்படுத்து';

  @override
  String get onboardingAddressCustomers => 'வாடிக்கையாளர்களை எப்படி அழைப்பது';

  @override
  String get onboardingAddressCustomersHint => 'பெயர் சொல்லும் வரை சார்/மேடம்';

  @override
  String get onboardingPoliciesTitle => 'விதிமுறைகளும் பொதுவான கேள்விகளும்';

  @override
  String get onboardingPoliciesBody =>
      'ஏஜென்ட் இவற்றைப் பின்பற்றும்; மற்றவை பற்றி உங்களிடம் கேட்கும்.';

  @override
  String get onboardingFulfilment => 'பிக்கப் மற்றும் டெலிவரி';

  @override
  String get onboardingFulfilmentHint =>
      'அண்ணா நகரில் பிக்கப், அல்லது அருகில் டெலிவரி';

  @override
  String get onboardingCustomOrders => 'தனிப்பயன் ஆர்டர்கள்';

  @override
  String get onboardingCustomOrdersHint =>
      'ஆம், 2 நாள் முன்னறிவிப்பு, 50% முன்பணம்';

  @override
  String get onboardingCancellations => 'ரத்து மற்றும் பணம் திருப்புதல்';

  @override
  String get onboardingNeverPromise =>
      'ஏஜென்ட் ஒருபோதும் வாக்குறுதி தரக்கூடாதவை';

  @override
  String get onboardingNeverPromiseHint =>
      'அன்றே தனிப்பயன் கேக், டெலிவரி நேரம்';

  @override
  String get onboardingFaqs => 'பொதுவான கேள்விகளும் பதில்களும்';

  @override
  String get onboardingFaqsHint => 'முட்டை இல்லாமல்? ஆம், கேட்டால்.';

  @override
  String get onboardingPaymentsTitle => 'பணம் செலுத்துதல்';

  @override
  String get onboardingPaymentsBody =>
      'ஏஜென்ட் எடுக்கும் ஆர்டர்களுக்கு வாடிக்கையாளர்கள் எப்படிப் பணம் செலுத்துவார்கள்.';

  @override
  String get onboardingPayPal => 'PayPal';

  @override
  String get onboardingPaymentsReady =>
      'தயார். வாடிக்கையாளர்களுக்குப் பணம் செலுத்தும் லிங்க் அனுப்பப்படும்; PayPal உறுதிசெய்ததும் ஆர்டர் \'பணம் செலுத்தப்பட்டது\' என மாறும்.';

  @override
  String get onboardingPaymentsNotReady =>
      'இன்னும் அமைக்கப்படவில்லை. அதுவரை, பணம் வந்ததை நீங்கள் உறுதிசெய்யும் வரை ஆர்டர்கள் காத்திருக்கும்.';
}
