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

  # Zone baselines shared with the Svelte MoveIcon — keep the two in sync.
  MOVE_ICON_ZONE_Y = { 3 => 3, 2 => 15, 1 => 31 }.freeze

  # A chunky inline-SVG glyph for one committed move, mirroring
  # MoveIcon.svelte: a stick figure with a red strike marker (kick wedge /
  # punch fist) or a blue guard bar at the low/mid/high zone.
  #
  # @param kind [Symbol] :attack or :block
  # @param height [Integer] 1 low, 2 mid, 3 high
  # @param style [Integer] 0 kick, 1 punch (attacks only)
  # @param size [Integer] rendered width in px
  # @return [ActiveSupport::SafeBuffer]
  def move_icon(kind:, height:, style: 0, size: 16)
    y = MOVE_ICON_ZONE_Y.fetch(height.to_i, 15)
    marker =
      if kind == :attack
        tip = if style.to_i.zero?
          %(<polygon points="7,#{y} 16,#{y + 4} 7,#{y + 9}"/>)
        else
          %(<rect x="8" y="#{y + 1}" width="7" height="7"/>)
        end
        %(<g fill="var(--kfm-belt-red)"><rect x="0" y="#{y + 3}" width="9" height="3"/>#{tip}</g>)
      else
        %(<rect x="11" y="#{y + 1}" width="20" height="6" fill="var(--kfm-belt-blue)"/>)
      end

    <<~SVG.html_safe
      <svg viewBox="0 0 36 44" width="#{size.to_i}" height="#{(size.to_i * 44.0 / 36).round}" aria-hidden="true"><g fill="currentColor" opacity="0.8"><rect x="17" y="1" width="8" height="8"/><rect x="18" y="10" width="6" height="16"/><rect x="14" y="12" width="14" height="3"/><rect x="17" y="27" width="3" height="15"/><rect x="22" y="27" width="3" height="15"/></g>#{marker}</svg>
    SVG
  end

  # A fight's move tuples ({Fight#scouting_moves_for}) as per-round attack+block
  # glyph pairs for a history-table cell.
  #
  # @param moves [Array<Array(Integer, Integer, Integer)>]
  # @return [ActiveSupport::SafeBuffer]
  def move_glyphs(moves)
    safe_join(
      moves.map do |attack_height, attack_style, block_height|
        content_tag(
          :span,
          move_icon(kind: :attack, height: attack_height, style: attack_style) +
            move_icon(kind: :block, height: block_height),
          class: "move-round"
        )
      end
    )
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
