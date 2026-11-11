module CoachApp
  module PackageJson
    def self.call(package)
      {
        id: package.id,
        name: package.name,
        description: package.description,
        pricePiastres: package.price_piastres,
        durationDays: package.duration_days,
        includes: package.includes,
        isActive: package.is_active,
        createdAt: package.created_at.iso8601
      }
    end
  end
end
