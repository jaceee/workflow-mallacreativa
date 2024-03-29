# encoding: utf-8
#
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

require File.expand_path('../../test_helper', __FILE__)

class OperationsControllerTest < ActionController::TestCase
  fixtures :projects,
           :users,
           :roles,
           :members,
           :member_roles,
           :issues,
           :issue_statuses,
           :versions,
           :trackers,
           :projects_trackers,
           :issue_categories,
           :enabled_modules,
           :enumerations,
           :attachments,
           :workflows,
           :custom_fields,
           :custom_values,
           :custom_fields_projects,
           :custom_fields_trackers,
           :time_entries,
           :journals,
           :journal_details,
           :queries

  RedmineFinance::TestCase.create_fixtures(Redmine::Plugin.find(:redmine_contacts).directory + '/test/fixtures/', [:contacts,
                                                                                                                   :contacts_projects,
                                                                                                                   :contacts_issues,
                                                                                                                   :deals,
                                                                                                                   :notes,
                                                                                                                   :tags,
                                                                                                                   :taggings,
                                                                                                                   :queries])
  if RedmineFinance.invoices_plugin_installed?
    RedmineFinance::TestCase.create_fixtures(Redmine::Plugin.find(:redmine_contacts_invoices).directory + '/test/fixtures/', [:invoices,
                                                                                                                              :invoice_lines])
  end

  RedmineFinance::TestCase.create_fixtures(Redmine::Plugin.find(:redmine_finance).directory + '/test/fixtures/', [:accounts,
                                                                                                                  :operations,
                                                                                                                  :operation_categories])

  def setup
    Setting.plugin_redmine_finance["finance_operations_approval"] = 0
    Project.find(1).enable_module!(:finance)
  end

  def test_should_get_index
    @request.session[:user_id] = 1
    get :index
    assert_response :success
    assert_template :index
    assert_not_nil assigns(:operations)
    assert_nil assigns(:project)
  end

  def test_should_get_show
    @request.session[:user_id] = 1
    get :show, :id => 1
    assert_response :success
    assert_template :show
    assert_not_nil assigns(:operation)
    assert_not_nil assigns(:project)
  end

  def test_should_get_new
    @request.session[:user_id] = 1
    get :new, :project_id => 1
    assert_response :success
    assert_template :new
    assert_not_nil assigns(:operation)
    assert_not_nil assigns(:project)
  end

  def test_should_get_edit
    @request.session[:user_id] = 1
    get :edit, :id => 1
    assert_response :success
    assert_template :edit
    assert_not_nil assigns(:operation)
    assert_not_nil assigns(:project)
  end

  def test_should_put_update
    @request.session[:user_id] = 1
    put :update, :id => 1, :operation => {:amount => 99.9}
    assert_response :redirect
    assert_equal 99.9, Operation.find(1).amount.to_f
  end

  def test_destroy
    @request.session[:user_id] = 1
    delete :destroy, :id => 1
    assert_redirected_to '/projects/ecookbook/operations'
    assert_nil Operation.find_by_id(1)
  end

  def test_should_post_create
    @request.session[:user_id] = 1
    assert_difference 'Operation.count' do
      post :create, :project_id => 1, :operation => {:description => "New operation description",
          :account_id => 1,
          :amount => 1000,
          :category_id => 1,
          :operation_date => Time.now}
      assert_response :redirect
    end
    assert_equal 1030, Operation.last.account.amount
    assert_equal "New operation description", Operation.last.description
  end

end
