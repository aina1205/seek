require 'test_helper'

class AssayClassTest < ActiveSupport::TestCase
  # Replace this with your real tests.
  fixtures :assay_classes
  test "for_type" do
    assert_equal "EXP",AssayClass.for_type("experimental").key
    assert_equal "MODEL",AssayClass.for_type("modelling").key
  end
end
