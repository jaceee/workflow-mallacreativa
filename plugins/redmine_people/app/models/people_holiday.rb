# This file is a part of Redmine People (redmine_people) plugin,
# humanr resources management plugin for Redmine
#
# Copyright (C) 2011-2017 RedmineUP
# http://www.redmineup.com/
#
# redmine_people is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# redmine_people is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with redmine_people.  If not, see <http://www.gnu.org/licenses/>.

class PeopleHoliday < ActiveRecord::Base
  unloadable
  include Redmine::SafeAttributes

  validates_presence_of :name, :start_date

  safe_attributes 'name',
                  'start_date',
                  'end_date',
                  'description',
                  'is_workday'

  def safe_attributes=(attrs, user=User.current)
    return unless attrs.is_a?(Hash)

    attrs = attrs.deep_dup
    attrs = delete_unsafe_attributes(attrs, user)
    return if attrs.empty?

    # mass-assignment security bypass
    assign_attributes attrs, :without_protection => true
  end

  def due_date
    end_date || start_date
  end

  def due_date=(date)
    self.end_date = date
  end
end
