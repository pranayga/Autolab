class Score < ApplicationRecord
  belongs_to :submission
  belongs_to :problem
  belongs_to :grader, class_name: "CourseUserDatum"

  after_save :invalidate_raw_score
  after_save :update_individual_grade_watchlist_instances_if_submission_latest,
             if: :saved_change_to_score_or_released?
  after_destroy :invalidate_raw_score
  after_destroy :update_individual_grade_watchlist_instances_if_submission_latest

  scope :on_latest_submissions, lambda {
                                  where(submissions: { ignored: false })
                                    .joins(submission: :assessment_user_datum)
                                }

  def self.for_course(course_id)
    where(assessments: { course_id: course_id }).joins(submission: :assessment)
  end

  delegate :invalidate_raw_score, to: :submission

  # Verifies that we will only ever have one score per problem per submission
  # This is what allows us to use submission.scores.maximum(:score,:group=>:problem_id) later on
  validates(:problem_id, uniqueness: { scope: :submission_id })
  validates :grader_id, presence: true

  after_commit :log_entry

  def self.find_with_feedback(*args)
    with_exclusive_scope { find(*args) }
  end

  # Requires submission_id, problem_id not null
  def self.find_or_initialize_by_submission_id_and_problem_id(submission_id, problem_id)
    if submission_id.nil? || problem_id.nil?
      raise InvalidScoreException.new, "submission_id and problem_id cannot be empty"
    end

    score = Score.find_by(submission_id: submission_id, problem_id: problem_id)

    if !score
      Score.new(submission_id: submission_id, problem_id: problem_id)
    else
      score
    end
  end

  def log_entry
    setter = if grader_id != 0
               grader.user.email
             else
               "Autograder"
             end

    # Some scores don't have submissions, probably if they're deleted ones
    return if submission.nil?

    COURSE_LOGGER.log("Score #{id} UPDATED for " \
    "#{submission.course_user_datum.user.email} set to " \
    "#{score} on #{submission.assessment.name}:#{problem.name} by" \
    " #{setter}")
  end

  def update_individual_grade_watchlist_instances_if_submission_latest
    # check whether score has been released
    submission.update_individual_grade_watchlist_instances_if_latest if released
  end

private

  def saved_change_to_score_or_released?
    (saved_change_to_score? or saved_change_to_released?)
  end
end
