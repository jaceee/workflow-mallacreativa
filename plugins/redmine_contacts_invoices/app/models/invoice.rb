# This file is a part of Redmine Invoices (redmine_contacts_invoices) plugin,
# invoicing plugin for Redmine
#
# Copyright (C) 2011-2017 RedmineUP
# https://www.redmineup.com/
#
# redmine_contacts_invoices is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# redmine_contacts_invoices is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with redmine_contacts_invoices.  If not, see <http://www.gnu.org/licenses/>.

class Invoice < ActiveRecord::Base
  unloadable
  include Redmine::SafeAttributes

  ESTIMATE_INVOICE = 0
  DRAFT_INVOICE = 1
  SENT_INVOICE = 2
  PAID_INVOICE = 3
  CANCELED_INVOICE = 4

  belongs_to :contact
  belongs_to :project
  belongs_to :author, :class_name => "User", :foreign_key => "author_id"
  belongs_to :assigned_to, :class_name => "User", :foreign_key => "assigned_to_id"
  belongs_to :template, :class_name => "InvoiceTemplate"
  has_many :lines, :class_name => "InvoiceLine", :foreign_key => "invoice_id", :order => "position", :dependent => :delete_all
  has_many :comments, :as => :commented, :dependent => :delete_all, :order => "created_on"
  has_many :payments, :class_name => "InvoicePayment", :dependent => :delete_all, :order => "payment_date"

  scope :by_project, lambda {|project_id| where(["#{Invoice.table_name}.project_id = ?", project_id]) unless project_id.blank? }
  scope :visible, lambda {|*args| eager_load(:project).where(Project.allowed_to_condition(args.first || User.current, :view_invoices)) }
  scope :live_search, lambda { |search| where("(LOWER(#{Invoice.table_name}.number) LIKE ? OR
                                                LOWER(#{Invoice.table_name}.subject) LIKE ? OR
                                                LOWER(#{Invoice.table_name}.description) LIKE ?)",
                                                "%" + search.downcase + "%",
                                                "%" + search.downcase + "%",
                                                "%" + search.downcase + "%") }

  scope :paid, lambda { where(:status_id => PAID_INVOICE) }
  scope :sent_or_paid, lambda { where(["#{Invoice.table_name}.status_id = ? OR #{Invoice.table_name}.status_id = ?", PAID_INVOICE, SENT_INVOICE]) }
  scope :open, lambda { where(["#{Invoice.table_name}.status_id <> ? AND #{Invoice.table_name}.status_id <> ?", PAID_INVOICE, CANCELED_INVOICE]) }

  if ActiveRecord::VERSION::MAJOR >= 4
    acts_as_activity_provider :type => 'invoices',
                              :permission => :view_invoices,
                              :timestamp => "#{table_name}.created_at",
                              :author_key => :author_id,
                              :scope => joins(:project)

    acts_as_searchable :columns => ["#{table_name}.number"],
                       :scope => joins(:project),
                       :project_key => "#{Project.table_name}.id",
                       :permission => :view_invoices,
                       # sort by id so that limited eager loading doesn't break with postgresql
                       :date_column => "number"
  else
    acts_as_activity_provider :type => 'invoices',
                              :permission => :view_invoices,
                              :timestamp => "#{table_name}.created_at",
                              :author_key => :author_id,
                              :find_options => {:include => :project}

    acts_as_searchable :columns => ["#{table_name}.number"],
                       :date_column => "#{table_name}.created_at",
                       :include => [:project],
                       :project_key => "#{Project.table_name}.id",
                       :permission => :view_invoices,
                       # sort by id so that limited eager loading doesn't break with postgresql
                       :order_column => "#{table_name}.number"
  end

  acts_as_event :datetime => :created_at,
                :url => Proc.new {|o| {:controller => 'invoices', :action => 'show', :id => o}},
                :type => 'icon-invoice',
                :title => Proc.new {|o| "#{l(:label_invoice_created)} ##{o.number} (#{o.status}): #{o.currency + ' ' if o.currency}#{o.amount}" },
                :description => Proc.new {|o| [o.number, o.contact ? o.contact.name : '', o.currency.to_s + " " + o.amount.to_s, o.description].join(' ') }

  acts_as_watchable
  acts_as_attachable
  acts_as_priceable :amount, :tax_amount, :discount_amount, :balance, :remaining_balance

  before_save :calculate_amount
  before_save :default_values

  validates_presence_of :number, :invoice_date, :project, :status_id
  validates_uniqueness_of :number
  validates_numericality_of :discount, :greater_than_or_equal_to => 0.0, :less_than_or_equal_to => 100.0, :allow_nil => true
  validate :validate_invoice

  accepts_nested_attributes_for :lines, :allow_destroy => true

  safe_attributes 'number',
    'subject',
    'invoice_date',
    'due_date',
    'currency',
    'language',
    'discount',
    'order_number',
    'contact_id',
    'status_id',
    'assigned_to_id',
    'project_id',
    'description',
    'lines_attributes',
    :if => lambda {|order, user| order.new_record? || user.allowed_to?(:edit_invoices, order.project) }

  def calculate_status
    self.calculate_balance
    if self.balance >= self.amount
      self.status_id = Invoice::PAID_INVOICE
      self.paid_date = self.payments.maximum(:payment_date)
    else
      self.status_id = Invoice::SENT_INVOICE
      self.paid_date = nil
    end
  end

  def calculate_balance
    payments_sum = self.payments.to_a.sum(&:amount)
    self.balance = payments_sum > self.amount ? self.amount : payments_sum
  end

  def calculate_amount
    self.amount = self.subtotal + (ContactsSetting.tax_exclusive? ? self.tax_amount : 0)
    if InvoicesSettings.discount_after_tax?
      self.amount -=  discount_amount
    end
    self.amount.to_f
  end
  alias_method :calculate, :calculate_amount

  def tax_amount
    self.lines.inject(0){|sum,x| sum + x.tax_amount * discount_rate}.to_f
  end

  def order
    if InvoicesSettings.products_plugin_installed? && !order_number.blank?
      Order.where(:number => order_number).first
    end
  end

  def subtotal
    if InvoicesSettings.discount_after_tax?
      self.lines.inject(0){|sum,x| sum + x.total}.to_f
    else
      self.lines.inject(0) do |sum,x|
        sum + (x.total - (x.total * (discount / 100)).to_f )
      end.to_f
    end
  end

  def discount_amount
    if InvoicesSettings.discount_after_tax?
      self.lines.inject(0){|sum,x| sum + x.total + x.tax_amount}.to_f * (discount / 100)
    else
      self.lines.inject(0) do |sum,x|
        sum + (x.total * (discount / 100)).to_f
      end.to_f
    end
  end

  def discount_rate
    InvoicesSettings.discount_after_tax? ? 1 : (1 - discount/100)
  end

  def discount
    read_attribute(:discount).to_f
  end

  def tax_groups
    self.lines.select{|l| !l.tax.blank? && l.tax.to_f > 0}.group_by{|l| l.tax}.map{|k, v| [k, v.sum{|l| l.tax_amount.to_f * discount_rate}] }
  end

  def visible?(usr=nil)
    (usr || User.current).allowed_to?(:view_invoices, self.project)
  end

  def editable_by?(usr, prj=nil)
    prj ||= @project || self.project
    usr && (usr.allowed_to?(:edit_invoices, prj) || (self.author == usr && usr.allowed_to?(:edit_own_invoices, prj)))
    # usr && usr.logged? && (usr.allowed_to?(:edit_notes, project) || (self.author == usr && usr.allowed_to?(:edit_own_notes, project)))
  end

  def destroyable_by?(usr, prj=nil)
    prj ||= @project || self.project
    usr && (usr.allowed_to?(:delete_invoices, prj) || (self.author == usr && usr.allowed_to?(:edit_own_invoices, prj)))
  end

  def commentable?(user=User.current)
    user.allowed_to?(:comment_invoices, project)
  end

  def total_with_tax?
    @total_with_tax ||= !InvoicesSettings.disable_taxes?(self.project) && InvoicesSettings.total_including_tax?
  end

  def copy_from(arg)
    invoice = arg.is_a?(Invoice) ? arg : Invoice.visible.find(arg)
    self.attributes = invoice.attributes.dup.except("id", "number", "created_at", "updated_at")
    self.lines = invoice.lines.collect{|l| InvoiceLine.new(l.attributes.dup.except("id", "created_at", "updated_at"))}
    self
  end

  def self.allowed_target_projects(user=User.current)
    Project.where(Project.allowed_to_condition(user, :edit_invoices))
  end

  STATUSES = {
    DRAFT_INVOICE => :label_invoice_status_draft,
    ESTIMATE_INVOICE => :label_invoice_status_estimate,
    SENT_INVOICE => :label_invoice_status_sent,
    PAID_INVOICE => :label_invoice_status_paid,
    CANCELED_INVOICE => :label_invoice_status_canceled
  }

  STATUSES_STRINGS = {
    DRAFT_INVOICE    => l(:label_invoice_status_draft),
    ESTIMATE_INVOICE => l(:label_invoice_status_estimate),
    SENT_INVOICE     => l(:label_invoice_status_sent),
    PAID_INVOICE     => l(:label_invoice_status_paid),
    CANCELED_INVOICE => l(:label_invoice_status_canceled)
  }

  def status
    l(STATUSES[status_id])
  end

  def set_status(st)
    STATUSES.respond_to?(:key) ? STATUSES.key(st) : STATUSES.index(st)
  end

  def is_draft
    status_id == DRAFT_INVOICE || status_id.blank?
  end

  def is_sent?
    status_id == SENT_INVOICE
  end

  def is_paid?
    status_id == PAID_INVOICE
  end

  def is_canceled?
     status_id == CANCELED_INVOICE
  end

  def is_estimate?
     status_id == ESTIMATE_INVOICE
  end

  def is_open?
    ![PAID_INVOICE, CANCELED_INVOICE].include?(status_id)
  end

  def editable?(usr=nil)
    @editable ||= editable_by?(usr)
  end

  def remaining_balance
    self.amount - self.balance
  end

  def has_taxes?
    !self.lines.map(&:tax).all?{|t| t == 0 || t.blank?}
  end

  def has_units?
    !self.lines.map(&:units).all?{|t| t == 0 || t.blank?}
  end

  def self.generate_invoice_number(project=nil)
    result = ''
    format = InvoicesSettings[:invoices_invoice_number_format, project].to_s
    if format
      result = format.gsub(/%%ID%%/, '%02d' % (Invoice.last.try(:id).to_i + 1).to_s)
      result = result.gsub(/%%YEAR%%/, Date.today.year.to_s)
      result = result.gsub(/%%MONTH%%/, '%02d' % Date.today.month.to_s)
      result = result.gsub(/%%DAY%%/, '%02d' % Date.today.day.to_s)
      result = result.gsub(/%%DAILY_ID%%/, '%02d' % (Invoice.where(:invoice_date => Time.now.to_time.utc.change(:hour => 0, :min => 0)).count + 1).to_s)
      result = result.gsub(/%%MONTHLY_ID%%/, '%03d' % (Invoice.where(:invoice_date => Time.now.beginning_of_month.utc.change(:hour => 0, :min => 0)..Time.now.end_of_month.utc.change(:hour => 0, :min => 0)).count + 1).to_s)
      result = result.gsub(/%%YEARLY_ID%%/, '%04d' % (Invoice.where(:invoice_date => Time.now.beginning_of_year.utc.change(:hour => 0, :min => 0)..Time.now.end_of_year.utc.change(:hour => 0, :min => 0)).count + 1).to_s)
      result = result.gsub(/%%MONTHLY_PROJECT_ID%%/, '%03d' % (Invoice.where(:project_id => project, :invoice_date => Time.now.beginning_of_month.utc.change(:hour => 0, :min => 0)..Time.now.end_of_month.utc.change(:hour => 0, :min => 0)).count + 1).to_s)
      result = result.gsub(/%%YEARLY_PROJECT_ID%%/, '%04d' % (Invoice.where(:project_id => project, :invoice_date => Time.now.beginning_of_year.utc.change(:hour => 0, :min => 0)..Time.now.end_of_year.utc.change(:hour => 0, :min => 0)).count + 1).to_s)
    end
    result
  end

  def filename
    "invoice-#{self.number.to_s}.pdf"
  end

  def self.sum_by_period(peroid, project, contact_id=nil)
    from, to = RedmineContacts::DateUtils.retrieve_date_range(peroid)
    scope = Invoice.where({})
    scope = scope.visible
    scope = scope.by_project(project.id) if project
    scope = scope.where("#{Invoice.table_name}.invoice_date >= ? AND #{Invoice.table_name}.invoice_date < ?", from, to)
    scope = scope.where("#{Invoice.table_name}.contact_id = ?", contact_id) unless contact_id.blank?
    scope = scope.sent_or_paid
    scope.group(:currency).sum(:amount)
  end

  def self.sum_by_status(status_id, project, contact_id=nil)
    scope = Invoice.where({})
    scope = scope.visible
    scope = scope.by_project(project.id) if project
    scope = scope.where("#{Invoice.table_name}.status_id = ?", status_id)
    scope = scope.where("#{Invoice.table_name}.contact_id = ?", contact_id) unless contact_id.blank?
    [scope.group(:currency).sum(:amount), scope.count(:number)]
  end

  def copy_from_object(copy_from_object, options={})
    return false if copy_from_object[:object].blank? && (copy_from_object[:object_type].blank? || copy_from_object[:object_id].blank?)
    klass = Object.const_get(copy_from_object[:object_type].camelcase) rescue nil unless copy_from_object[:object_type].blank?
    from_object = copy_from_object[:object] || klass.find(copy_from_object[:object_id])
    self.contact = from_object.contact if from_object.respond_to?(:contact)
    self.currency = from_object.currency if from_object.respond_to?(:currency)
    self.order_number = from_object.order_number if from_object.respond_to?(:order_number)
    if from_object.respond_to?(:lines)
      from_object.lines.each do |line|
        new_line = self.lines.new
        new_line.position = line.position if line.respond_to?(:position) && line.position
        new_line.description = line.description if line.respond_to?(:description) && line.description.present?
        new_line.tax = line.tax if line.respond_to?(:tax) && line.tax
        new_line.quantity = line.quantity if line.respond_to?(:quantity) && line.quantity
        new_line.discount = line.discount if line.respond_to?(:discount) && line.discount
        new_line.price = line.price.to_f * (1 - new_line.discount.to_f / 100) if line.respond_to?(:price)
        new_line.product_id = line.product_id if line.respond_to?(:product_id) && line.product_id
      end
    end

  end

  def overdue?
    is_sent? && due_date && (due_date <= Date.current)
  end

  def contact_country
    self.try(:contact).try(:address).try(:country)
  end

  def contact_city
    self.try(:contact).try(:address).try(:city)
  end

  def notified_users
    [author, assigned_to].reject(&:nil?)
  end

  def recurring_instances_sum
    return recurring_instances.sum(:amount) if is_recurring
    return recurring_profile.recurring_instances.sum(:amount) if recurring_instance?
    0
  end

  def recurring_instances_due_sum
    return recurring_instances.map(&:remaining_balance).sum if is_recurring
    return recurring_profile.recurring_instances.map(&:remaining_balance).sum if recurring_instance?
    0
  end

  private

  def default_values
    self.discount = 0 unless read_attribute(:discount)
  end

  def validate_invoice
    if (status_id != PAID_INVOICE && remaining_balance == 0 && balance > 0) || (status_id == PAID_INVOICE && remaining_balance > 0 && amount > 0)
      errors.add :status_id, :text_invoice_cant_change_status
    end
  end
end
