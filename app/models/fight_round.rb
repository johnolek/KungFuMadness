class FightRound < ApplicationRecord
  belongs_to :fight

  validates :round, inclusion: { in: 1..3 }, uniqueness: { scope: :fight_id }
  validates :challenger_damage, :opponent_damage,
            :challenger_hp_after, :opponent_hp_after,
            presence: true, numericality: { only_integer: true }
end
