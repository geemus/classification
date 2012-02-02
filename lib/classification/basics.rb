@categories_counts = Hash.new(0)
@tokens_counts = Hash.new {|hash,key| hash[key] = Hash.new(0)}
def tokenize(string)
  string.downcase!
  string.squeeze!(' ')
  string.gsub!(/[^a-z]\s/, ' ')

  tokens = Hash.new(0)
  string.split(' ').each do |token|
    tokens[token] += 1
  end
  tokens
end

class Category
  ASSUMED = 0.5

  @categories = {}

  def self.[](category)
    @categories[category] ||= Category.new(category)
  end

  def self.categories
    @categories
  end

  def self.delete(category)
    @categories.delete(category).tokens.each do |key, count|
      @tokens[key] -= count
    end
    true
  end

  def self.match(tokens)
    probabilities = {}
    @categories.each do |name, category|
      probabilities[name] = category.match(tokens)
    end
    probabilities
  end

  @tokens = Hash.new(0.0)

  def self.tokens
    @tokens
  end

  def self.tokens=(new_tokens)
    @tokens = new_tokens
  end

  attr_accessor :name, :tokens, :total

  def initialize(name)
    @name, @tokens, @total_category_tokens = name, Hash.new(0.0), 0.0
  end

  def match(tokens)
    if @total_category_tokens == 0.0
      probability = ASSUMED
    else
      probability = 1.0
      tokens.each do |token, count|
        total_tokens = self.class.tokens[token]
        conditional = @tokens[token] / @total_category_tokens

        weighted = (total_tokens * conditional + 1.0 * ASSUMED) / (total_tokens + 1)
        count.times do
          probability *= weighted
        end
      end
    end
    probability
  end

  def update(tokens)
    tokens.each do |token, count|
      Category.tokens[token] += count
      @tokens[token] += count
      @total_category_tokens += count
    end
  end
end

#[
#  {'money' => 1}
#].each {|tokens| Category['bad'].update(tokens)}
#
#[
#  {}
#].each {|tokens| Category['good'].update(tokens)}
#
#p Category.match('money' => 1)
#p Category['bad'].match('money' => 1)
#p Category['good'].match('money' => 1)
