require "simple_memoize"

# This represents a deployable region (e.g. "sandbox1" or "sandbox2") and all builds associated with that region.
# Columns:
#   - ordinal: the ordering position of this region within an app's list of regions. Every region in the app
#     should have a different ordinal number. "prod1" should have 0, "prod2" should have 1, etc.
class Region < Sequel::Model
  unrestrict_primary_key

  many_to_one :application
  one_to_many :builds, :key => :current_region_id
  one_to_many :build_statuses
  add_association_dependencies :builds => :destroy, :build_statuses => :destroy

  # The build in this region which is currently in progress.
  def in_progress_build
    active_states = ["deploying", "testing", "monitoring", "awaiting_confirmation"]
    builds_dataset.reverse_order(:id).filter(:state => active_states).first
  end

  # The next build in line that's awaiting deploy. TODO(philc): Rename this.
  def next_build
    builds_dataset.order(:id.desc).first(:state => "awaiting_deploy")
  end

  def build_history
    build_statuses_dataset.order(:id.desc).limit(10).all
  end

  def requires_manual_approval?() requires_manual_approval end
  def requires_monitoring?() requires_monitoring end

  memoize :next_build, :in_progress_build, :build_history
end