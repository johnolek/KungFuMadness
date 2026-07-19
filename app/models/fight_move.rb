class FightMove < ApplicationRecord
  HEIGHTS = { low: 1, mid: 2, high: 3 }.freeze
  STYLES = { kick: 0, punch: 1 }.freeze

  belongs_to :fight
  belongs_to :fighter

  validates :round, inclusion: { in: 1..3 }
  validates :attack_height, inclusion: { in: HEIGHTS.values }
  validates :block_height, inclusion: { in: HEIGHTS.values }
  validates :attack_style, inclusion: { in: STYLES.values }
  validates :fighter_id, uniqueness: { scope: [ :fight_id, :round ] }
end
