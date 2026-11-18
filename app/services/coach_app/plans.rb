module CoachApp
  # Coach plan authoring against the shared DB. A coach reaches only their own clients' plans
  # (through their subscriptions). `publish!` replicates Node's publishPlan transactionally:
  # version bump, previous published → replaced, subscription → active, and a `plan_ready`
  # client notification row — so a Rails-published plan reads back identically through Node.
  module Plans
    PUBLISHABLE = %w[awaiting_plan active].freeze

    # The plan the coach is authoring: their draft if any, else the published one, else the most
    # recent version (so editing a past plan is possible). Nil when none exists yet.
    def self.show(coach, subscription_id)
      subscription = find_subscription!(coach, subscription_id)
      plan = Plan.find_by(subscription_id: subscription.id, status: "draft") ||
             Plan.find_by(subscription_id: subscription.id, status: "published") ||
             Plan.where(subscription_id: subscription.id).order(version: :desc).first
      plan && PlanJson.call(plan)
    end

    # Upsert the subscription's single draft (not visible to the client), replacing its contents.
    def self.save_draft!(coach, subscription_id, attrs)
      subscription = find_subscription!(coach, subscription_id)
      input = PlanInput.validate(attrs, Foods.visible_by_id(coach))

      plan = Plan.transaction do
        draft = Plan.find_by(subscription_id: subscription.id, status: "draft")
        if draft
          draft.plan_options.delete_all # DB cascade clears meals + components
          draft.update!(notes: input[:notes])
        else
          draft = Plan.create!(
            subscription_id: subscription.id,
            version: next_version(subscription.id),
            status: "draft",
            notes: input[:notes],
          )
        end
        insert_tree!(draft, input[:options])
        draft
      end
      PlanJson.call(plan)
    end

    # Publish a plan for the subscription (mirrors Node's publishPlan).
    def self.publish!(coach, subscription_id, attrs)
      subscription = find_subscription!(coach, subscription_id)
      input = PlanInput.validate(attrs, Foods.visible_by_id(coach))
      if flagged?(input)
        raise ApiError.new(409, "plan has unchecked lines")
      end
      sizes = Portions.sizes_for(coach)
      now = Time.current

      plan = Plan.transaction do
        sub = Subscription.lock.find(subscription.id)
        unless PUBLISHABLE.include?(sub.status) && sub.ends_at > now
          raise ApiError.new(409, "subscription not ready for a plan")
        end

        Plan.where(subscription_id: sub.id, status: "draft").delete_all
        version = next_version(sub.id)
        Plan.where(subscription_id: sub.id, status: "published").update_all(status: "replaced")
        published = Plan.create!(
          subscription_id: sub.id,
          version: version,
          status: "published",
          notes: input[:notes],
          published_at: now,
        )
        insert_tree!(published, input[:options], sizes)
        sub.update!(status: "active")
        notify_plan_ready!(sub, coach, published, version)
        published
      end
      PlanJson.call(plan)
    end

    def self.find_subscription!(coach, subscription_id)
      coach.subscriptions.find_by(id: subscription_id) ||
        raise(ApiError.new(404, "client not found"))
    end
    private_class_method :find_subscription!

    def self.next_version(subscription_id)
      (Plan.where(subscription_id: subscription_id).maximum(:version) || 0) + 1
    end
    private_class_method :next_version

    def self.insert_tree!(plan, options, sizes = nil)
      options.each_with_index do |opt, oi|
        option = PlanOption.create!(plan_id: plan.id, position: oi + 1, label: opt[:label], notes: opt[:notes])
        opt[:meals].each do |meal|
          row = PlanMeal.create!(
            plan_option_id: option.id,
            slot: meal[:slot],
            position: meal[:position],
            title: meal[:title],
            notes: meal[:notes],
          )
          meal[:components].each_with_index do |c, ci|
            PlanMealComponent.create!(
              plan_meal_id: row.id,
              position: ci + 1,
              kind: c[:kind],
              food_id: c[:food_id],
              quantity: c[:quantity],
              unit: c[:unit],
              preparation: c[:preparation],
              macro: c[:macro],
              macro_grams: snapshot_grams(c, sizes),
              portion_group: c[:portion_group],
              portion_count: c[:portion_count],
              free_text: c[:free_text],
              import_flag: c[:import_flag],
            )
          end
        end
      end
    end
    private_class_method :insert_tree!

    # Publish freezes portion targets (so later size changes don't move a published plan);
    # drafts (sizes nil) leave them null and track the coach's current sizes.
    def self.snapshot_grams(component, sizes)
      return component[:macro_grams] unless component[:kind] == "portion"
      return nil unless sizes

      grams = Portions.target_grams(component[:portion_group], component[:portion_count], sizes)
      grams && format("%.2f", grams)
    end
    private_class_method :snapshot_grams

    def self.flagged?(input)
      input[:options].any? { |o| o[:meals].any? { |m| m[:components].any? { |c| c[:import_flag] } } }
    end
    private_class_method :flagged?

    # Same row shape Node writes from publishPlan (recordClientNotification).
    def self.notify_plan_ready!(subscription, coach, plan, version)
      first = version == 1
      Notification.create!(
        recipient_type: "client",
        recipient_id: subscription.client_id,
        type: "plan_ready",
        title: first ? "خطتك جاهزة" : "تم تحديث خطتك",
        body: first ? "نشر #{coach.full_name} خطتك. افتحها لترى وجبات اليوم." \
                    : "نشر #{coach.full_name} نسخة جديدة من خطتك.",
        data: { "subscriptionId" => subscription.id, "planId" => plan.id },
      )
    end
    private_class_method :notify_plan_ready!
  end
end
