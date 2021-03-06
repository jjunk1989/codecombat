require('app/styles/user/certificates-view.sass')
RootView = require 'views/core/RootView'
User = require 'models/User'
Classroom = require 'models/Classroom'
Course = require 'models/Course'
CourseInstance = require 'models/CourseInstance'
LevelSessions = require 'collections/LevelSessions'
Levels = require 'collections/Levels'
ThangTypeConstants = require 'lib/ThangTypeConstants'
ThangType = require 'models/ThangType'
utils = require 'core/utils'
fetchJson = require 'core/api/fetch-json'
NameLoader = require 'core/NameLoader'

module.exports = class CertificatesView extends RootView
  id: 'certificates-view'
  template: require 'templates/user/certificates-view'

  events:
    'click .print-btn': 'onClickPrintButton'

  getTitle: ->
    return 'Certificate' if @user.broadName() is 'Anonymous'
    "Certificate: #{@user.broadName()}"

  initialize: (options, @userID) ->
    if @userID is me.id
      @user = me
      @setHero()
    else
      @user = new User _id: @userID
      @user.fetch()
      @supermodel.trackModel @user
      @listenToOnce @user, 'sync', => @setHero?()
    if classroomID = utils.getQueryVariable 'class'
      @classroom = new Classroom _id: classroomID
      @classroom.fetch()
      @supermodel.trackModel @classroom
      @listenToOnce @classroom, 'sync', @onClassroomLoaded
    if courseID = utils.getQueryVariable 'course'
      @course = new Course _id: courseID
      @course.fetch()
      @supermodel.trackModel @course
    @courseInstanceID = utils.getQueryVariable 'course-instance'
    # TODO: anonymous loading of classrooms and courses with just enough info to generate cert, or cert route on server
    # TODO: handle when we don't have classroom & course
    # TODO: add a check here that the course is completed

    @sessions = new LevelSessions()
    @supermodel.trackRequest @sessions.fetchForCourseInstance @courseInstanceID, userID: @userID, data: { project: 'state.complete,level.original,playtime,changed,code,codeLanguage,team' }
    @listenToOnce @sessions, 'sync', @calculateStats
    @courseLevels = new Levels()
    @supermodel.trackRequest @courseLevels.fetchForClassroomAndCourse classroomID, courseID, data: { project: 'concepts,practice,assessment,primerLanguage,type,slug,name,original,description,shareable,i18n,thangs.id,thangs.components.config.programmableMethods' }
    @listenToOnce @courseLevels, 'sync', @calculateStats

  setHero: (heroOriginal=null) ->
    heroOriginal ||= utils.getQueryVariable('hero') or @user.get('heroConfig')?.thangType or ThangTypeConstants.heroes.captain
    @thangType = new ThangType()
    @supermodel.trackRequest @thangType.fetchLatestVersion(heroOriginal, {data: {project:'slug,version,original,extendedName,heroClass'}})
    @thangType.once 'sync', (thangType) =>
      if @thangType.get('heroClass') isnt 'Warrior' or @thangType.get('slug') is 'code-ninja'
        # We only have basic warrior poses and signatures for now
        @setHero ThangTypeConstants.heroes.captain

  onClassroomLoaded: ->
    @calculateStats()
    Promise.resolve($.ajax(NameLoader.loadNames([@classroom.get 'ownerID']))).then =>
      @teacherName = NameLoader.getName @classroom.get 'ownerID'
      @render()

  getCodeLanguageName: ->
    return 'Code' unless @classroom
    if @course and /web-dev-1/.test @course.get('slug')
      return 'HTML/CSS'
    if @course and /web-dev/.test @course.get('slug')
      return 'HTML/CSS/JS'
    return @classroom.capitalizeLanguageName()

  calculateStats: ->
    return unless @classroom.loaded and @sessions.loaded and @courseLevels.loaded
    @courseStats = @classroom.statsForSessions @sessions, @course.id, @courseLevels

    if @courseStats.levels.project
      projectSession = @sessions.find (session) => session.get('level').original is @courseStats.levels.project.get('original')
      if projectSession
        @projectLink = "#{window.location.origin}/play/#{@courseStats.levels.project.get('type')}-level/#{projectSession.id}"
        fetchJson('/db/level.session/short-link', method: 'POST', json: {url: @projectLink}).then (response) =>
          @projectShortLink = response.shortLink
          @render()

  onClickPrintButton: ->
    window.print()

  afterRender: ->
    @autoSizeText '.student-name'

  autoSizeText: (selector) ->
    @$(selector).each (index, el) ->
      while el.scrollWidth > el.offsetWidth or el.scrollHeight > el.offsetHeight
        newFontSize = (parseFloat($(el).css('font-size').slice(0, -2)) * 0.95) + 'px'
        $(el).css('font-size', newFontSize)
