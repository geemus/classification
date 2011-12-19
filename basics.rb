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

  @categories = []

  def self.categories
    @categories
  end

  def self.categories=(new_categories)
    @categories = new_categories
  end

  def self.match(tokens)
    probabilities = {}
    @categories.each do |category|
      probabilities[category.name] = category.match(tokens)
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

  attr_accessor :name

  def initialize(name)
    @name, @tokens, @total = name, Hash.new(0.0), 0.0
    Category.categories |= [self]
  end

  def match(tokens)
    if @total == 0.0
      probability = ASSUMED
    else
      probability = 1.0
      tokens.each do |token, count|
        total = self.class.tokens[token]
        conditional = @tokens[token] / @total

        weighted = (total * conditional + 1.0 * ASSUMED) / (total + 1)
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
      @total += count
    end
  end
end

bad = Category.new('bad')
[
  {'money' => 1}
].each {|tokens| bad.update(tokens)}


good = Category.new('good')
[
  {}
].each {|tokens| good.update(tokens)}

p Category.match('money' => 1)
p bad.match('money' => 1)
p good.match('money' => 1)
