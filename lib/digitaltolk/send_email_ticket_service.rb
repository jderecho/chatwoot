class Digitaltolk::SendEmailTicketService
  attr_accessor :account, :user, :params, :errors, :conversation, :for_issue

  CUSTOMER_TYPE = 2
  TRANSLATOR_TYPE = 3
  
  def initialize(account, user, params, for_issue: false)
    @account = account
    @user = user
    @params = params
    @errors = []
    @for_issue = for_issue
  end

  def perform
    begin
      ActiveRecord::Base.transaction do
        validate_params
        find_or_create_conversation
        validate_data
        create_message
      end
    rescue StandardError => e
      Rails.logger.error e
      Rails.logger.error e.backtrace.first
      @errors << e.message
    end

    result_data
  end

  private

  def result_data
    return result_json(true, "Email sent!") if @errors.blank?

    result_json(false, @errors.join(", "))
  end

  def result_json(success, message)
    {
      success: success,
      message: message,
      conversation_id: @conversation&.display_id
    }
  end

  def conversations
    inbox.conversations
  end

  def conversation_params
    {
      subject: params.dig(:title),
      content: params.dig(:body),
      inbox_id: params.dig(:inbox_id),
      email: params.dig(:requester, :email),
      assignee_id: nil,
      account_id: @account.id,
    }
  end

  def find_or_create_conversation
    return if @errors.present?

    if for_customer?
      @conversation = conversations.where("custom_attributes ->> 'booking_id' = ?", booking_id).last

      if @conversation.blank?
        create_conversation
        assign_booking_id
        assign_booking_issue_id if for_issue
      end
    elsif for_translator?
      create_conversation
      assign_booking_id
      assign_booking_issue_id if for_issue
    end
  end

  def create_conversation
    @conversation = Digitaltolk::AddConversationService.new(inbox_id, conversation_params).perform
  end

  def assign_booking_id
    @conversation.custom_attributes['booking_id'] = booking_id
    @conversation.save
  end

  def assign_booking_issue_id
    @conversation.custom_attributes['booking_issue_id'] = booking_issue_id
    @conversation.save
  end

  def for_customer?
    recipient_type.to_i == CUSTOMER_TYPE
  end

  def for_translator?
    recipient_type.to_i == TRANSLATOR_TYPE
  end

  def recipient_type
    params.dig(:recipient_type)
  end

  def inbox
    @inbox ||= @account.inboxes.find_by(id: inbox_id)
  end

  def inbox_id
    params.dig(:inbox_id)
  end

  def booking_id
    params.dig(:booking_id).to_s
  end

  def booking_issue_id
    params.dig(:booking_issue_id).to_s
  end

  def validate_params
    if booking_id.blank?
      @errors << "Parameter booking_id is required"
    end

    if recipient_type.blank?
      @errors << "Recipient Type is required"
    elsif !for_customer? && !for_translator?
      @errors << "Unknown recipient_type #{recipient_type}"
    end

    if inbox.blank?
      @errors << "Inbox with id #{inbox_id} was not found"
    end
  end

  def validate_data
    return if @errors.blank?

    @errors << invalid_booking_message if @conversation.blank?
  end

  def invalid_booking_message
    "Conversation with booking ID #{booking_id} not found"
  end

  def create_message
    return if @errors.present?

    @message = Digitaltolk::AddMessageService.new(@user, @conversation, @params.dig(:body)).perform
  end
end