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

class ProductsDrop < ::Liquid::Drop

  def self.default_drop
    self.new Product.all
  end

  def initialize(products)
    @products = products
  end

  def before_method(code)
    product = @products.where(:code => code).first || Product.new
    ProductDrop.new product
  end

  def all
    @all ||= @products.map do |product|
      ProductDrop.new product
    end
  end

  def visible
    @visible ||= @products.visible.map do |product|
      ProductDrop.new product
    end
  end

  def each(&block)
    all.each(&block)
  end

end


class ProductDrop < ::Liquid::Drop
end
