require "test_helper"

class DuplicateFinderTest < ActiveSupport::TestCase
  setup { @project = keila_projects(:alpha) }

  def add(email, **attrs)
    @project.contacts.create!(email: email, **attrs)
  end

  def pairs
    DuplicateFinder.for_project(@project).map { |pair| [ [ pair.contact.email, pair.other.email ].sort, pair.reasons ] }
  end

  test "finds the same address with a typo in the domain" do
    add("info@kfh-dialyse.de")
    add("info@kfh-dialysse.de")

    assert_equal [ [ %w[info@kfh-dialysse.de info@kfh-dialyse.de].sort, [ :similar_domain ] ] ], pairs
  end

  test "finds the same address under another top level domain or a subdomain" do
    add("info@kfh.de")
    add("info@kfh.com")
    add("info@mail.kfh.de")

    assert_equal [ %w[info@kfh.com info@kfh.de], %w[info@kfh.de info@mail.kfh.de] ], pairs.map(&:first).sort
  end

  test "keeps distinct short domains apart" do
    add("max@gmx.de")
    add("max@web.de")

    assert_empty pairs
  end

  test "finds near-identical names before the @ at the same domain" do
    add("max.muster@example.org")
    add("maxmuster+news@example.org")
    add("max.muser@example.org")
    add("moritz@example.org")

    assert_equal [ %w[max.muser@example.org max.muster@example.org],
                   %w[max.muser@example.org maxmuster+news@example.org],
                   %w[max.muster@example.org maxmuster+news@example.org] ], pairs.map(&:first).sort
  end

  test "finds the same person under two addresses, regardless of umlauts and name order" do
    add("hm@example.org", first_name: "Hans", last_name: "Müller")
    add("hans@other.example", first_name: "Mueller", last_name: "Hans")
    add("solo@example.net", first_name: "Hans")

    assert_equal [ [ %w[hans@other.example hm@example.org], [ :same_name ] ] ], pairs
  end

  test "lists each pair once with every reason that applies" do
    add("info@kfh-dialyse.de", first_name: "Kuratorium", last_name: "Heimdialyse")
    add("info@kfh-dialysse.de", first_name: "Kuratorium", last_name: "Heimdialyse")

    assert_equal [ [ %w[info@kfh-dialysse.de info@kfh-dialyse.de].sort, %i[similar_domain same_name] ] ], pairs
  end

  test "leaves out dismissed pairs and other projects' contacts" do
    a = add("info@kfh-dialyse.de")
    b = add("info@kfh-dialysse.de")
    keila_projects(:beta).contacts.create!(email: "info@kfh-dialyze.de")

    DuplicateDismissal.dismiss!(b, a)

    assert_empty pairs
  end

  test "for_contact only returns pairs with that contact" do
    a = add("info@kfh-dialyse.de")
    add("info@kfh-dialysse.de")
    add("office@example.org")
    add("offize@example.org")

    found = DuplicateFinder.for_contact(a)

    assert_equal 1, found.size
    assert_includes found.first.contact_ids, a.id
  end
end
