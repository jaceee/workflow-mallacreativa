# This file is a part of Redmine Finance (redmine_finance) plugin,
# simple accounting plugin for Redmine
#
# Copyright (C) 2011-2016 Kirill Bezrukov
# http://www.redminecrm.com/
#
# redmine_finance is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# redmine_finance is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with redmine_finance.  If not, see <http://www.gnu.org/licenses/>.

class OperationQuery < CrmQuery
  include RedmineCrm::MoneyHelper
  include OperationsHelper

  self.queried_class = Operation

  self.available_columns = [
    QueryColumn.new(:operation_date, :caption => :label_operation_date, :frozen => true),
    QueryColumn.new(:income, :caption => :label_operation_income, :frozen => true),
    QueryColumn.new(:expense, :caption => :label_operation_expense, :frozen => true),
    QueryColumn.new(:description, :frozen => true),
    QueryColumn.new(:account, :sortable => "#{Account.table_name}.name", :groupable => true, :caption => :label_account),
    QueryColumn.new(:category, :sortable => "#{Operation.table_name}.category_id", :groupable => true, :caption => :field_operation_category),
    QueryColumn.new(:contact, :sortable => lambda {Contact.fields_for_order_statement}, :groupable => true, :caption => :label_contact),
    QueryColumn.new(:author, :sortable => lambda {User.fields_for_order_statement("authors")})
  ]

  def initialize(attributes=nil, *args)
    super attributes
    self.filters ||= RedmineFinance.operations_approval? ? { 'is_approved' => {:operator => "=", :values => ["1"]} } : {}
    @currenct_connection = ActiveRecord::VERSION::MAJOR >= 4 ? self.class.connection : connection
  end

  def initialize_available_filters
    add_available_filter "is_approved", :type => :list, :values => [[l(:general_text_yes), "1"], [l(:general_text_no), "0"]], :label => :label_finance_is_approved if RedmineFinance.operations_approval?
    add_available_filter "operation_type", :type => :list, :values => [[l(:label_operation_income), "1"], [l(:label_operation_expense), "0"]], :label => :label_operation_type

    add_available_filter "operation_date", :type => :date, :label => :label_operation_date

    operation_categories = []
    OperationCategory.category_tree(OperationCategory.order(:lft)) do |operation_category, level|
      name_prefix = (level > 0 ? '-' * 2 * level + ' ' : '').html_safe #'&nbsp;'
      operation_categories << [(name_prefix + operation_category.name).html_safe, operation_category.id.to_s]
    end
    add_available_filter("category_id", :type => :list, :label => :label_operation_category,
      :values => operation_categories
    ) if operation_categories.any?

    add_available_filter("contact_id",
      :type => :list, :values => operations_contacts_for_select(project), :label => :label_contact
    )

    add_available_filter("account_id",
      :type => :list, :values => accounts_for_select(project), :label => :label_account
    )
    add_associations_custom_fields_filters :contact, :author, :assigned_to
  end

  def available_columns
    return @available_columns if @available_columns
    @available_columns = self.class.available_columns.dup
    @available_columns += CustomField.where(:type => 'OperationCustomField').all.map {|cf| QueryCustomFieldColumn.new(cf) }
    @available_columns += CustomField.where(:type => 'ContactCustomField').all.map {|cf| QueryAssociationCustomFieldColumn.new(:contact, cf) }
    @available_columns
  end

  def default_columns_names
    @default_columns_names ||= [:operation_date, :account, :category, :description, :contact]
  end

  def sql_for_operation_type_field(field, operator, value)
    op = (operator == "=" ? 'IN' : 'NOT IN')
    va = value.map {|v| v == '0' ? @currenct_connection.quoted_false : @currenct_connection.quoted_true}.uniq.join(',')

    "#{Operation.table_name}.income #{op} (#{va})"
  end

  def sql_for_currency_field(field, operator, value)
    sql_for_field(field, operator, value, Account.table_name, field)
  end

  def sql_for_category_id_field(field, operator, value)
    category_ids = value
    category_ids += OperationCategory.where(:id => value).map(&:descendants).flatten.collect{|c| c.id.to_s}.uniq
    sql_for_field(field, operator, category_ids, Operation.table_name, "category_id")
  end

  def income_amount
    objects_scope.income.group("#{Account.table_name}.currency").sum(:amount)
  rescue ::ActiveRecord::StatementInvalid => e
    raise StatementInvalid.new(e.message)
  end

  def expense_amount
    objects_scope.expense.group("#{Account.table_name}.currency").sum(:amount)
  rescue ::ActiveRecord::StatementInvalid => e
    raise StatementInvalid.new(e.message)
  end


  def objects_scope(options={})
    scope = Operation.visible
    options[:search].split(' ').collect{ |search_string| scope = scope.live_search(search_string) } unless options[:search].blank?
    scope = scope.includes((query_includes + (options[:include] || [])).uniq).
      where(statement).
      where(options[:conditions])
    scope
  end

  def results_scope(options={})
    order_option = [group_by_sort_order, "#{Operation.table_name}.operation_date DESC", options[:order]].flatten.reject(&:blank?)

    objects_scope(options).
      order(order_option).
      joins(joins_for_order_statement(order_option.join(','))).
      limit(options[:limit]).
      offset(options[:offset])
  rescue ::ActiveRecord::StatementInvalid => e
    raise StatementInvalid.new(e.message)
  end

  def query_includes
    includes = [:category, :contact, {:account => :project}]
    includes << :assigned_to if self.filters["assigned_to_id"] || (group_by_column && [:assigned_to].include?(group_by_column.name))
    includes
  end

end
