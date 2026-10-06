module ApplicationHelper
  # The page numbers a pager shows: the first and last page and a few
  # around the current one, with nil where pages are left out, e.g.
  # [1, nil, 6, 7, 8, 9, 10, nil, 40] for page 8 of 40. A gap of a single
  # page shows that page instead.
  def pagination_window(page, total_pages, around: 2)
    numbers = ([ 1, total_pages ] + ((page - around)..(page + around)).to_a)
      .select { |number| number.between?(1, total_pages) }.uniq.sort
    numbers.each_cons(2).flat_map do |a, b|
      case b - a
      when 1 then [ a ]
      when 2 then [ a, a + 1 ]
      else [ a, nil ]
      end
    end + numbers.last(1)
  end
end
