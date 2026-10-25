/// Ready-made promotional messages. {name} becomes the customer's name and {shop} the restaurant's name.
const promoTemplates = <String, String>{
  'promo_t_sale': 'Assalam o Alaikum {name}! {shop} mein aaj special sale hai. Aaiye aur lutf uthaiye!',
  'promo_t_deal': 'Assalam o Alaikum {name}! {shop} ki nayi Deal aa gayi hai. Order karne ke liye hamein call ya WhatsApp karein.',
  'promo_t_thanks': 'Assalam o Alaikum {name}! {shop} ko chunne ka shukriya. Dobara tashreef layein!',
  'promo_t_offer': 'Assalam o Alaikum {name}! Sirf aap ke liye {shop} ki taraf se khaas offer. Is message ko dikha kar discount hasil karein.',
};

/// The message for one customer.
String promoMessage(String template, {required String name, required String shop}) =>
    template.replaceAll('{name}', name.trim().isEmpty ? '' : name.trim()).replaceAll('{shop}', shop.trim()).replaceAll(RegExp(r' {2,}'), ' ').replaceAll(' !', '!').trim();

class PromoTarget {
  const PromoTarget({required this.name, required this.phone});
  final String name;
  final String phone;
}

/// One-by-one sending: WhatsApp opens with the message typed in; the person presses Send and comes back for the next one.
/// Nothing is sent without a person pressing Send in WhatsApp, and a number is never messaged twice in one run.
class PromoQueue {
  PromoQueue(Iterable<PromoTarget> targets, {required this.template, required this.shop}) {
    final seen = <String>{};
    for (final t in targets) {
      final digits = t.phone.replaceAll(RegExp(r'\D'), '');
      if (digits.isEmpty || !seen.add(digits)) continue;
      _targets.add(t);
    }
  }
  final String template;
  final String shop;
  final _targets = <PromoTarget>[];
  int _index = 0;

  int get total => _targets.length;
  int get done => _index;
  bool get finished => _index >= _targets.length;
  PromoTarget? get current => finished ? null : _targets[_index];
  String? get currentText => finished ? null : promoMessage(template, name: _targets[_index].name, shop: shop);

  /// Moves on to the next customer (after sending or skipping).
  void advance() {
    if (!finished) _index++;
  }
}
