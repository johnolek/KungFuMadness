module ApplicationHelper
  # All-time count of resolved fights, cached briefly — the footer's retro
  # "visitor counter" now reflects real dojo activity. Zero-padded for flavor.
  #
  # @return [String] a 9-digit, zero-padded count, e.g. "000000452"
  def resolved_fight_tally
    count = Rails.cache.fetch("resolved_fight_tally", expires_in: 5.minutes) { Fight.resolved.count }
    format("%09d", count)
  end

  # Server flash mapped to props for the Toasts island.
  #
  # @param flash [ActionDispatch::Flash::FlashHash]
  # @return [Hash]
  def toast_props(flash)
    toasts = flash.map { |type, message| { type: type, message: message } }
    { toasts: toasts }
  end

  # A fighter's name for HTML display. Bots get a subtle, dimmed "[BOT]" tag after
  # the name so they're identifiable everywhere without an emoji.
  #
  # @param fighter [Fighter]
  # @return [ActiveSupport::SafeBuffer]
  def fighter_display_name(fighter)
    return h(fighter.name) unless fighter.bot?

    safe_join([ fighter.name, content_tag(:span, "[BOT]", class: "bot-tag") ], " ")
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

  # A fighter's name rendered AS their belt — a belt-colored chip whose label is
  # the display name. This replaces the separate name + belt-chip pair in every
  # roster/feed/table surface.
  #
  # @param fighter [Fighter]
  # @param belt [Integer, nil] snapshot belt override (defaults to current belt)
  # @return [ActiveSupport::SafeBuffer]
  def fighter_name_chip(fighter, belt: nil)
    belt_chip(belt || fighter.belt, label: fighter_display_name(fighter))
  end

  # {fighter_name_chip} wrapped in a profile link (no underline — the chip is the
  # visual affordance).
  #
  # @param fighter [Fighter]
  # @param belt [Integer, nil] snapshot belt override
  # @return [ActiveSupport::SafeBuffer]
  def fighter_name_link(fighter, belt: nil)
    link_to fighter_name_chip(fighter, belt: belt), fighter_path(fighter), class: "belt-link"
  end

  # The current-form callout, e.g. "3-fight win streak" — nil when there's no
  # history to describe.
  #
  # @param streak [Hash, nil] { result:, length: } from {Scouting#streak}
  # @return [String, nil]
  def streak_callout(streak)
    return nil if streak.nil? || streak[:length].zero?

    word = { "W" => "win", "L" => "loss", "D" => "draw" }.fetch(streak[:result], "")
    plural = streak[:length] == 1 ? "fight" : "fights"
    "#{streak[:length]}-#{plural} #{word} streak"
  end
end
