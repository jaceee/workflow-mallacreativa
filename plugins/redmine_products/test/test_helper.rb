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

# Load the Redmine helper
require File.expand_path(File.dirname(__FILE__) + '/../../../test/test_helper')

class RedmineProducts::TestCase
  include ActionDispatch::TestProcess

  def self.create_fixtures(fixtures_directory, table_names, class_names = {})
    if ActiveRecord::VERSION::MAJOR >= 4
      ActiveRecord::FixtureSet.create_fixtures(fixtures_directory, table_names, class_names = {})
    else
      ActiveRecord::Fixtures.create_fixtures(fixtures_directory, table_names, class_names = {})
    end
  end

  def self.prepare
    Setting.plugin_redmine_contacts["thousands_delimiter"] = ","
    Setting.plugin_redmine_contacts["decimal_separator"] = '.'
    Project.where(:id => [1, 5]).each do |project|
      EnabledModule.create(:project => project, :name => 'orders')
      EnabledModule.create(:project => project, :name => 'products')
      EnabledModule.create(:project => project, :name => 'contacts')
      EnabledModule.create(:project => project, :name => 'deals')
    end

    Role.where(:id => [1, 2, 3, 4]).each do |r|
      r.permissions << :view_contacts
      r.save
    end

    Role.where(:id => [1, 2]).each do |r|
      # user_2, user_3
      r.permissions << :add_products
      r.permissions << :view_products
      r.save
    end

    Role.where(:id => [1]).each do |r|
      # user_2
      r.permissions << :import_products
      r.save
    end
  end
end
