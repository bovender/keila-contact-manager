require "did_you_mean"

# Finds pairs of contacts in one project that are probably the same
# subscriber. Exact duplicates can't exist -- both this app and Keila keep
# emails unique per project, ignoring case -- so what's left to find are
# near misses: a typo in the domain (info@kfh-dialysse.de next to
# info@kfh-dialyse.de), in the part before the @, or the same person
# signed up under two addresses. These are suggestions for the duplicates
# page, not rules: pairs the user marked as "not duplicates"
# (DuplicateDismissal) are left out.
class DuplicateFinder
  # `reasons` is a list of REASONS keys; `contact` is the older of the two.
  Pair = Struct.new(:contact, :other, :reasons) do
    def contact_ids
      [ contact.id, other.id ]
    end
  end

  REASONS = {
    similar_domain: "Same name before the @, similar domain",
    similar_local_part: "Same domain, similar name before the @",
    same_name: "Same first and last name"
  }.freeze

  def self.for_project(project)
    new(project.contacts.to_a, dismissed: DuplicateDismissal.pairs_for(project)).pairs
  end

  def self.for_contact(contact)
    for_project(contact.keila_project).select { |pair| pair.contact_ids.include?(contact.id) }
  end

  def initialize(contacts, dismissed: Set.new)
    @contacts = contacts
    @dismissed = dismissed
  end

  def pairs
    @found = {}

    each_pair_in(@contacts.group_by { |c| local_part(c.email) }) do |a, b|
      note(a, b, :similar_domain) if similar_domains?(domain(a.email), domain(b.email))
    end
    each_pair_in(@contacts.group_by { |c| domain(c.email) }) do |a, b|
      note(a, b, :similar_local_part) if similar_local_parts?(local_part(a.email), local_part(b.email))
    end
    each_pair_in(@contacts.group_by { |c| name_key(c) }.except(nil)) do |a, b|
      note(a, b, :same_name)
    end

    @found.values.sort_by { |pair| [ pair.contact.email, pair.other.email ] }
  end

  private

  def each_pair_in(groups, &block)
    groups.each_value { |members| members.combination(2, &block) if members.size > 1 }
  end

  def note(a, b, reason)
    a, b = [ a, b ].sort_by(&:id)
    return if @dismissed.include?([ a.id, b.id ])

    (@found[[ a.id, b.id ]] ||= Pair.new(a, b, [])).reasons |= [ reason ]
  end

  def local_part(email)
    email.to_s.split("@", 2).first.to_s
  end

  def domain(email)
    email.to_s.split("@", 2).second.to_s
  end

  # kfh-dialyse.de ~ kfh-dialysse.de (typo), kfh.de ~ kfh.com (other top
  # level domain), kfh.de ~ mail.kfh.de (subdomain). Short domains get
  # less leeway, so that e.g. gmx.de and web.de stay apart.
  def similar_domains?(a, b)
    return false if a == b || a.blank? || b.blank?
    return true if a.end_with?(".#{b}") || b.end_with?(".#{a}")
    return true if without_tld(a) == without_tld(b)

    distance(a, b) <= ([ a.length, b.length ].min < 8 ? 1 : 2)
  end

  # Ignoring dots, dashes, underscores and a "+suffix": max.muster ~
  # maxmuster ~ max.muster+news; beyond that, one typo (max.muser).
  def similar_local_parts?(a, b)
    a = normalized_local_part(a)
    b = normalized_local_part(b)
    return true if a == b

    [ a.length, b.length ].min >= 4 && distance(a, b) <= 1
  end

  def normalized_local_part(local)
    local.sub(/\+.*/, "").delete("._-")
  end

  def without_tld(domain)
    domain.sub(/\.[^.]+\z/, "")
  end

  # Both names are needed, so that a lone common first name doesn't pair
  # up half the list. Order doesn't matter ("Muster Max" is "Max
  # Muster"), and neither do umlauts and accents ("Müller" is "Mueller").
  def name_key(contact)
    return nil if contact.first_name.blank? || contact.last_name.blank?

    name = "#{contact.first_name} #{contact.last_name}".downcase
      .gsub("ä", "ae").gsub("ö", "oe").gsub("ü", "ue").gsub("ß", "ss")
    I18n.transliterate(name).gsub(/[^a-z ]/, " ").split.sort.join(" ").presence
  end

  def distance(a, b)
    DidYouMean::Levenshtein.distance(a, b)
  end
end
