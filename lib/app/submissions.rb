class ExercismApp < Sinatra::Base

  helpers do
    def nitpick(id)
      submission = Submission.find(id)

      if current_user.guest?
        halt 403, "You're not logged in right now. Go back, copy the text, log in, and try again. Sorry about that."
      end

      unless current_user.owns?(submission) || current_user.may_nitpick?(submission.exercise)
        halt 403, "You do not have permission to nitpick that exercise."
      end

      nitpick = Nitpick.new(id, current_user, params[:comment], approvable: params[:approvable])
      nitpick.save
      if nitpick.nitpicked?
        #TODO - create emails from notifications
        Notify.everyone(submission, current_user, 'nitpick')
        flash[:success] = 'This submission has been nominated for approval' if nitpick.approvable?
        begin
          unless nitpick.nitpicker == nitpick.submission.user
            NitpickMessage.ship(
              instigator: nitpick.nitpicker,
              submission: nitpick.submission,
              site_root: site_root
            )
          end
        rescue => e
          puts "Failed to send email. #{e.message}."
        end
      end
    end

    def approve(id)
      if current_user.guest?
        halt 403, "You're not logged in right now, so I can't let you do that. Sorry."
      end

      submission = Submission.find(id)
      unless current_user.unlocks?(submission.exercise)
        halt 403, "You do not have permission to approve that exercise."
      end

      Notify.source(submission, current_user, 'approval')

      begin
        unless current_user == submission.user
          ApprovalMessage.ship(
            instigator: current_user,
            submission: submission,
            site_root: site_root
          )
        end
      rescue => e
        puts "Failed to send email. #{e.message}."
      end
      Approval.new(id, current_user, params[:comment]).save
    end

    def toggle_opinions(id, state)
      submission = Submission.find(id)

      unless current_user.owns?(submission)
        flash[:error] = "You do not have permission to do that."
        redirect '/'
      end
      
      submission.send("#{state}_opinions!")

      flash[:notice] =  if submission.wants_opinions?
                          "Your request for more opinions has been made! You can disable this below when all is clear."
                        else
                          "Your request for more opinions has been disabled!"
                        end
    end
  end

  get '/user/submissions/:id' do |id|
    redirect "/submissions/#{id}"
  end

  get '/submissions/:id' do |id|
    please_login "/submissions/#{id}"

    submission = Submission.find(id)

    title(submission.slug + " in " + submission.language + " by " + submission.user.username)


    unless current_user.owns?(submission) || current_user.may_nitpick?(submission.exercise)
      flash[:error] = "You do not have permission to nitpick that exercise."
      redirect '/'
    end

    erb :nitpick, locals: {submission: submission}
  end

  # TODO: Write javascript to submit form here
  post '/submissions/:id/nitpick' do |id|
    nitpick(id)
    redirect '/'
  end

  # TODO: Write javascript to submit form here
  post '/submissions/:id/approve' do |id|
    approve(id)
    redirect '/'
  end

  # I don't like this, but I don't see how to make
  # the front-end to be able to use the same textarea for two purposes
  # without it. It seems like this is a necessary
  # fallback even if we implement the javascript stuff.
  post '/submissions/:id/respond' do |id|
    if params[:approve]
      approve(id)
    else
      nitpick(id)
    end
    redirect "/submissions/#{id}"
  end

  post '/submissions/:id/opinions/enable' do |id|
    please_login "/submissions/#{id}/opinions/enable"
    toggle_opinions(id, :enable)
    redirect "/submissions/#{id}"
  end

  post '/submissions/:id/opinions/disable' do |id|
    please_login "/submissions/#{id}/opinions/disable"
    toggle_opinions(id, :disable)
    redirect "/submissions/#{id}"
  end

  get '/submissions/:id/nits/:nit_id/edit' do |id, nit_id|
    submission = Submission.find(id)
    nit = submission.nits.where(id: nit_id).first
    redirect "/submissions/#{id}" unless current_user == nit.nitpicker
    erb :edit_nit, locals: {submission: submission, nit: nit}
  end

  post '/submissions/:id/nits/:nit_id/edit' do |id, nit_id|
    nit = Submission.find(id).nits.where(id: nit_id).first
    nit.sanitized_update(params['comment'])
    redirect "/submissions/#{id}"
  end

  get '/submissions/:language/:assignment' do |language, assignment|
    please_login "/submissions/#{language}/#{assignment}"

    unless current_user.locksmith?
      flash[:notice] = "Sorry, need to know only."
      redirect '/'
    end

    submissions = Submission.where(l: language, s: assignment)
                            .in(state: ["pending", "approved"])
                            .includes(:user)
                            .desc(:at).to_a

    erb :submissions_for_assignment, locals: { submissions: submissions,
                                                  language: language,
                                                assignment: assignment }
  end
end
