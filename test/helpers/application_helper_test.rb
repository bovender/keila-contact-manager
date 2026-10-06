require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "pagination_window shows the ends and the pages around the current one" do
    assert_equal [ 1, nil, 6, 7, 8, 9, 10, nil, 40 ], pagination_window(8, 40)
    assert_equal [ 1, 2, 3, nil, 40 ], pagination_window(1, 40)
    assert_equal [ 1, nil, 38, 39, 40 ], pagination_window(40, 40)
  end

  test "pagination_window shows a single left-out page instead of a gap" do
    assert_equal [ 1, 2, 3, 4, 5, 6 ], pagination_window(4, 6)
  end

  test "pagination_window with few pages shows them all" do
    assert_equal [ 1 ], pagination_window(1, 1)
    assert_equal [ 1, 2, 3 ], pagination_window(2, 3)
  end
end
