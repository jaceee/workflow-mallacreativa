# encoding: utf-8
#
# This file is a part of Redmine Products (redmine_products) plugin,
# customer relationship management plugin for Redmine
#
# Copyright (C) 2011-2017 RedmineUP
# http://www.redmineup.com/
#
# redmine_products is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# redmine_products is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with redmine_products.  If not, see <http://www.gnu.org/licenses/>.

require File.dirname(__FILE__) + '/../../test_helper'

class Redmine::ApiTest::ProductsTest < ActiveRecord::VERSION::MAJOR >= 4 ? Redmine::ApiTest::Base : ActionController::IntegrationTest
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

  RedmineProducts::TestCase.create_fixtures(Redmine::Plugin.find(:redmine_contacts).directory + '/test/fixtures/', [:contacts,
                                                                                                                    :contacts_projects])

  RedmineProducts::TestCase.create_fixtures(Redmine::Plugin.find(:redmine_products).directory + '/test/fixtures/', [:products,
                                                                                                                    :order_statuses,
                                                                                                                    :orders,
                                                                                                                    :product_categories,
                                                                                                                    :product_lines])

  def setup
    Setting.rest_api_enabled = '1'
    RedmineProducts::TestCase.prepare
  end

  def test_get_products_xml
    # Use a private project to make sure auth is really working and not just
    # only showing public issues.
    Redmine::ApiTest::Base.should_allow_api_authentication(:get, "/projects/private-child/products.xml") if ActiveRecord::VERSION::MAJOR < 4

    get '/products.xml', {}, credentials('admin')

    assert_tag :tag => 'products',
      :attributes => {
        :type => 'array',
        :total_count => assigns(:products_count),
        :limit => 25,
        :offset => 0
      }
  end


  def test_post_products_xml
    parameters = {:product => {:project_id => 1, :code => 'api_test_002', :name => "API test product"}}
    if ActiveRecord::VERSION::MAJOR < 4
      Redmine::ApiTest::Base.should_allow_api_authentication(:post,
                                      '/products.xml',
                                      parameters,
                                      {:success_code => :created})
    end

    assert_difference('Product.count') do
      post '/products.xml', parameters, credentials('admin')
    end

    product = Product.order('id DESC').first
    assert_equal parameters[:product][:code], product.code

    assert_response :created
    assert_equal 'application/xml', @response.content_type
    assert_tag 'product', :child => {:tag => 'id', :content => product.id.to_s}
  end

  def test_put_products_1_xml
    parameters = {:product => {:code => 'CODE_UPDATED'}}

    if ActiveRecord::VERSION::MAJOR < 4
      Redmine::ApiTest::Base.should_allow_api_authentication(:put,
                                    '/products/1.xml',
                                    parameters,
                                    {:success_code => :ok})
    end

    assert_no_difference('Product.count') do
      put '/products/1.xml', parameters, credentials('admin')
    end

    product = Product.find(1)
    assert_equal parameters[:product][:code], product.code

  end

end
