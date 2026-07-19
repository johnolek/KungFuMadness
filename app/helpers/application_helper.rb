module ApplicationHelper
  # Server flash mapped to props for the Toasts island.
  #
  # @param flash [ActionDispatch::Flash::FlashHash]
  # @return [Hash]
  def toast_props(flash)
    toasts = flash.map { |type, message| { type: type, message: message } }
    { toasts: toasts }
  end

  # A belt-colored name chip. Fills with the index-aligned --belt-N var; light
  # belts get dark text, dark belts get light text for contrast.
  #
  # @param belt [Integer] belt index
  # @param label [String, nil] override text (defaults to the belt name)
  # @return [ActiveSupport::SafeBuffer]
  def belt_chip(belt, label: nil)
    dark_text = belt <= 3
    content_tag(
      :span,
      label || Belt.name_for(belt),
      class: "belt-chip",
      style: "background: var(--belt-#{[ belt, 9 ].min}); color: #{dark_text ? 'var(--kfm-ink)' : 'var(--kfm-parchment)'};"
    )
  end

  # The index-aligned CSS var reference for a belt fill color.
  #
  # @param belt [Integer]
  # @return [String] e.g. "var(--belt-5)"
  def belt_var(belt)
    "var(--belt-#{[ belt, 9 ].min})"
  end
end
