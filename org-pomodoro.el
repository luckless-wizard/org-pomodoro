;;; org-pomodoro.el --- Pomodoro implementation for org-mode.

;; org-pomodoro.el fork

;; date here
;; See information on fork github concerning revisions provided by fork
;; Forked by: Andrew Metzner <luckless-wizard@riseup.net>
;; URL: github here

;; Author: Arthur Leonard Andersen <leoc.git@gmail.com>, Marcin Koziej <marcin at lolownia dot org>
;; URL: https://github.com/lolownia/org-pomodoro
;; Created: May 10, 2013
;; Package-Version: 20220318.1618
;; Package-Revision: 3f5bcfb80d61
;; Package-Requires: ((alert "0.5.10") (cl-lib "0.5"))

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:

;; Org-pomodoro introduces an easy way to clock time in org-mode with
;; the pomodoro technique.  You can clock into tasks with starting a
;; pomodoro time automatically.  Each finished pomodoro is followed by
;; a break timer.  If you completed 4 pomodoros in a row the break is
;; longer that the shorter break between each pomodoro.
;;
;; For a full explanation of the pomodoro technique, have a look at:
;;   http://www.pomodorotechnique.com

;;; Code:
(eval-when-compile
  (require 'cl-lib))

(require 'timer)
(require 'org)
(require 'org-agenda)
(require 'org-clock)
(require 'org-timer)
(require 'alert)

;;; Custom Variables

(defgroup org-pomodoro nil
  "Org pomodoro customization"
  :tag "Org Pomodoro"
  :group 'org-progress)

(defcustom org-pomodoro-auto-start t
  "If non-nil, automatically start a new pomodoro after each break.
If nil, prompt the user and wait."
  :group 'org-pomodoro
  :type 'boolean)

(defcustom org-pomodoro-long-break-frequency 4
  "The maximum number of pomodoros until a long break is started."
  :group 'org-pomodoro
  :type 'integer)

(defcustom org-pomodoro-ask-upon-killing t
  "Determines whether to ask upon killing a pomodoro or not."
  :group 'org-pomodoro
  :type 'boolean)

(defcustom org-pomodoro-play-sounds t
  "Determines whether sounds are played or not."
  :group 'org-pomodoro
  :type 'boolean)

(defcustom org-pomodoro-manual-break nil
  "Whether the user needs to exit manually
from a running pomodoro to enter a break.

If non-nil, after the time is up for a pomodoro, an \"overtime\"
state is entered until ‘org-pomodoro’ is invoked, which then
finishes the pomodoro and enters the break period."
  :group 'org-pomodoro
  :type 'boolean)

;; Pomodoro Values

(defcustom org-pomodoro-length 25
  "The length of a pomodoro in minutes."
  :group 'org-pomodoro
  :type 'integer)

(defcustom org-pomodoro-time-format "%.2m:%.2s"
  "Defines the format of the time representation in the modeline."
  :group 'org-pomodoro
  :type 'string)

(defcustom org-pomodoro-format "Pomodoro~%s"
  "The format of the mode line string during a pomodoro session."
  :group 'org-pomodoro
  :type 'string)

(defcustom org-pomodoro-audio-player
  (cond
   ((executable-find "aplay") "aplay")
   ((executable-find "afplay") "afplay")
   ;; WSL fallback: use powershell.exe (full path not needed if in PATH)
   ((and (eq system-type 'gnu/linux)
         (string-match-p "Microsoft" (shell-command-to-string "uname -r")))
    "powershell.exe")
   (t nil))
  "Music player used to play sounds.
On WSL, falls back to powershell.exe to play audio."
  :group 'org-pomodoro
  :type 'string)


;;; POMODORO START SOUND
(defcustom org-pomodoro-start-sound-p nil
  "Determines whether to play a sound when a pomodoro started.

Use `org-pomodoro-start-sound' to determine what sound that should be."
  :group 'org-pomodoro
  :type 'boolean)

(defcustom org-pomodoro-start-sound (when load-file-name
                                      (concat (file-name-directory load-file-name)
                                              "resources/bell.wav"))
  "The path to a sound file that´s to be played when a pomodoro is started."
  :group 'org-pomodoro
  :type 'file)

(defcustom org-pomodoro-start-sound-args nil
  "Arguments used when playing the `org-pomodoro-start-sound'."
  :group 'org-pomodoro
  :type 'string)


;;; POMODORO FINISHED SOUND
(defcustom org-pomodoro-finished-sound-p t
  "Determines whether to play a sound when a pomodoro finished.

Use `org-pomodoro-finished-sound' to determine what sound that should be."
  :group 'org-pomodoro
  :type 'boolean)

(defcustom org-pomodoro-finished-sound (when load-file-name
                                         (concat (file-name-directory load-file-name)
                                                 "resources/bell.wav"))
  "The path to a sound file that´s to be played when a pomodoro was finished."
  :group 'org-pomodoro
  :type 'file)

(defcustom org-pomodoro-finished-sound-args nil
  "Arguments used when playing the `org-pomodoro-finished-sound'."
  :group 'org-pomodoro
  :type 'string)

;;; POMODORO OVERTIME SOUND
(defcustom org-pomodoro-overtime-sound-p t
  "Determines whether to play a sound when a pomodoro starts to run overtime.

Use `org-pomodoro-overtime-sound' to determine what sound that should be."
  :group 'org-pomodoro
  :type 'boolean)

(defcustom org-pomodoro-overtime-sound (when load-file-name
                                         (concat (file-name-directory load-file-name)
                                                 "resources/bell.wav"))
  "The path to a sound file that´s to be played when a pomodoro runs overtime."
  :group 'org-pomodoro
  :type 'file)

(defcustom org-pomodoro-overtime-sound-args nil
  "Arguments used when playing the `org-pomodoro-overtime-sound'."
  :group 'org-pomodoro
  :type 'string)

;;; POMODORO KILLED SOUND
(defcustom org-pomodoro-killed-sound-p nil
  "Determines whether to play a sound when a pomodoro killed.

Use `org-pomodoro-killed-sound' to determine what sound that should be."
  :group 'org-pomodoro
  :type 'boolean)

(defcustom org-pomodoro-killed-sound nil
  "The path to a sound file, that´s to be played when a pomodoro is killed."
  :group 'org-pomodoro
  :type 'file)

(defcustom org-pomodoro-killed-sound-args nil
  "Arguments used when playing the `org-pomodoro-killed-sound'."
  :group 'org-pomodoro
  :type 'string)

;;; POMODORO SHORT-BREAK SOUND
(defcustom org-pomodoro-short-break-sound-p t
  "Determines whether to play a sound when a short-break finished.

Use `org-pomodoro-short-break-sound' to determine what sound that should be."
  :group 'org-pomodoro
  :type 'boolean)

(defcustom org-pomodoro-clock-break nil
  "When t, also clocks time during breaks."
  :group 'org-pomodoro
  :type 'boolean)

(defcustom org-pomodoro-short-break-sound (when load-file-name
                                            (concat (file-name-directory load-file-name)
                                                    "resources/bell.wav"))
  "The path to a sound file that´s to be played when a break was finished."
  :group 'org-pomodoro
  :type 'file)

(defcustom org-pomodoro-short-break-sound-args nil
  "Arguments used when playing the `org-pomodoro-short-break-sound'."
  :group 'org-pomodoro
  :type 'string)

;;; POMODORO LONG-BREAK SOUND
(defcustom org-pomodoro-long-break-sound-p t
  "Determines whether to play a sound when a long-break finished.

Use `org-pomodoro-long-break-sound' to determine what sound that should be."
  :group 'org-pomodoro
  :type 'boolean)

(defcustom org-pomodoro-long-break-sound (when load-file-name
                                           (concat (file-name-directory load-file-name)
                                                   "resources/bell_multiple.wav"))
  "The path to a sound file that´s to be played when a long break is finished."
  :group 'org-pomodoro
  :type 'file)

(defcustom org-pomodoro-long-break-sound-args nil
  "Arguments used when playing the `org-pomodoro-long-break-sound'."
  :group 'org-pomodoro
  :type 'string)

;;; POMODORO TICKING SOUND
(defcustom org-pomodoro-ticking-sound-p nil
  "Determines whether ticking sounds are played or not."
  :group 'org-pomodoro
  :type 'boolean)

(defcustom org-pomodoro-ticking-sound (when load-file-name
                                        (concat (file-name-directory load-file-name)
                                                "resources/tick.wav"))
  "The path to a sound file that´s to be played while a pomodoro is running."
  :group 'org-pomodoro
  :type 'file)

(defcustom org-pomodoro-ticking-sound-args nil
  "Arguments used when playing the `org-pomodoro-ticking-sound'."
  :group 'org-pomodoro
  :type 'string)

(defcustom org-pomodoro-ticking-sound-states '(:pomodoro :short-break :long-break)
  "The states in which to play ticking sounds."
  :group 'org-pomodoro
  :type 'list)

(defcustom org-pomodoro-ticking-frequency 1
  "The frequency at which to playback the ticking sound."
  :group 'org-pomodoro
  :type 'list)

;;; OVERTIME VALUES
(defcustom org-pomodoro-overtime-format "+%s"
  "The format of the mode line during a pomodoro running overtime."
  :group 'org-pomodoro
  :type 'string)

;;; BREAK VALUES
(defcustom org-pomodoro-short-break-length 5
  "The length of a short break in minutes."
  :group 'org-pomodoro
  :type 'integer)

(defcustom org-pomodoro-short-break-format "Short Break~%s"
  "The format of the mode line string during a short break."
  :group 'org-pomodoro
  :type 'string)

(defcustom org-pomodoro-long-break-length 20
  "The length of a long break in minutes."
  :group 'org-pomodoro
  :type 'integer)

(defcustom org-pomodoro-long-break-format "Long Break~%s"
  "The format of the mode line string during a long break."
  :group 'org-pomodoro
  :type 'string)

(defcustom org-pomodoro-expiry-time 120
  "The time in minutes for which a pomodoro group is valid.
The size of a pomodoro group is defined by `org-pomodoro-long-break-frequency'.

If you do not clock in for this period of time you will be prompted
whether to reset the pomodoro count next time you call `org-pomodoro'."
  :group 'org-pomodoro
  :type 'integer)

(defcustom org-pomodoro-keep-killed-pomodoro-time nil
  "Keeps the clocked time of killed pomodoros."
  :group 'org-pomodoro
  :type 'boolean)

;; Hooks

(defvar org-pomodoro-original-task-marker nil
  "Marker pointing to the original task started with `org-pomodoro`.")

(defvar org-pomodoro-started-hook nil
  "Hooks run when a pomodoro is started.")

(defvar org-pomodoro-finished-hook nil
  "Hooks run when a pomodoro is finished.")

(defvar org-pomodoro-overtime-hook nil
  "Hooks run when a pomodoro enters overtime.")

(defvar org-pomodoro-killed-hook nil
  "Hooks run when a pomodoro is killed.")

(defvar org-pomodoro-break-finished-hook nil
  "Hook run after any break has finished.
Run before a break's specific hook.")

(defvar org-pomodoro-long-break-finished-hook nil
  "Hooks run when a long break is finished.")

(defvar org-pomodoro-short-break-finished-hook nil
  "Hooks run when short break is finished.")

(defvar org-pomodoro-tick-hook nil
  "Hooks run every second during a pomodoro.")

;; Faces

(defface org-pomodoro-mode-line
  '((t (:foreground "tomato1")))
  "Face of a pomodoro in the modeline."
  :group 'faces)

(defface org-pomodoro-mode-line-overtime
  '((t (:foreground "tomato3" :weight bold)))
  "Face of a pomodoro running overtime in the modeline."
  :group 'faces)

(defface org-pomodoro-mode-line-break
  '((t (:foreground "#2aa198")))
  "Face of a pomodoro break in the modeline ."
  :group 'faces)

;; Temporary Variables

(defvar org-pomodoro-mode-line "")
(put 'org-pomodoro-mode-line 'risky-local-variable t)

(defvar org-pomodoro-timer nil
  "The timer while a pomodoro or a break.")

(defvar org-pomodoro-end-time nil
  "The end time of the current pomodoro phase.")

(defvar org-pomodoro-state :none
  "The current state of `org-pomodoro`.
It changes to :pomodoro when starting a pomodoro and to :longbreak
or :break when starting a break.")

(defvar org-pomodoro-count 0
  "The number of pomodoros since the last long break.")

(defvar org-pomodoro-last-clock-in nil
  "The last time the pomodoro was set.")

;;; Internal

;; Helper Functions

(defun org-pomodoro-active-p ()
  "Retrieve whether org-pomodoro is active or not."
  (not (eq org-pomodoro-state :none)))

(defun org-pomodoro-expires-p ()
  "Return true when the last clock-in was more than `org-pomodoro-expiry-time`."
  (let ((delta-minutes (/ (float-time (time-subtract (current-time) org-pomodoro-last-clock-in)) 60)))
    (> delta-minutes org-pomodoro-expiry-time)))

(defun org-pomodoro-sound-p (type)
  "Return whether to play sound of given TYPE."
  (cl-case type
    (:start org-pomodoro-start-sound-p)
    (:pomodoro org-pomodoro-finished-sound-p)
    (:overtime org-pomodoro-overtime-sound-p)
    (:killed org-pomodoro-killed-sound-p)
    (:short-break org-pomodoro-short-break-sound-p)
    (:long-break org-pomodoro-long-break-sound-p)
    (:tick org-pomodoro-ticking-sound-p)
    (t (error "Unknown org-pomodoro sound: %S" type))))

(defun org-pomodoro-sound (type)
  "Return the sound file for given TYPE."
  (cl-case type
    (:start org-pomodoro-start-sound)
    (:pomodoro org-pomodoro-finished-sound)
    (:overtime org-pomodoro-overtime-sound)
    (:killed org-pomodoro-killed-sound)
    (:short-break org-pomodoro-short-break-sound)
    (:long-break org-pomodoro-long-break-sound)
    (:tick org-pomodoro-ticking-sound)
    (t (error "Unknown org-pomodoro sound: %S" type))))

(defun org-pomodoro-sound-args (type)
  "Return the playback arguments for given TYPE."
  (cl-case type
    (:start org-pomodoro-start-sound-args)
    (:pomodoro org-pomodoro-finished-sound-args)
    (:overtime org-pomodoro-overtime-sound-args)
    (:killed org-pomodoro-killed-sound-args)
    (:short-break org-pomodoro-short-break-sound-args)
    (:long-break org-pomodoro-long-break-sound-args)
    (:tick org-pomodoro-ticking-sound-args)
    (t (error "Unknown org-pomodoro sound: %S" type))))

;; (defun org-pomodoro-play-sound (type)
;;   "Play an audio file specified by TYPE (:pomodoro, :short-break, :long-break)."
;;   (let ((sound (org-pomodoro-sound type))
;;         (args (org-pomodoro-sound-args type)))
;;     (when sound
;;       (cond
;;        ;; WSL case: use PowerShell to play sound
;;        ((and (org-pomodoro--running-in-wsl-p) org-pomodoro-play-sounds)
;;         (org-pomodoro--wsl-play-sound sound))

;;        ;; Use sound-wav-play if available and enabled
;;        ((and (fboundp 'sound-wav-play)
;;              org-pomodoro-play-sounds)
;;         (sound-wav-play sound))

;;        ;; Use audio player command with arguments
;;        ((and org-pomodoro-audio-player
;;              org-pomodoro-play-sounds)
;;         (start-process-shell-command
;;          "org-pomodoro-audio-player" nil
;;          (mapconcat 'identity
;;                     `(,org-pomodoro-audio-player
;;                       ,@(delq nil (list args (shell-quote-argument (expand-file-name sound)))))
;;                     " ")))))))

(defun org-pomodoro--running-in-wsl-p ()
  "Detect if Emacs is running inside WSL."
  (with-temp-buffer
    (insert-file-contents "/proc/version" nil 0 1024)
    (goto-char (point-min))
    (search-forward "Microsoft" nil t)))

(defun org-pomodoro--wsl-play-sound (sound-path)
  "Play SOUND-PATH using PowerShell in WSL."
  (let* ((win-path
          (replace-regexp-in-string
           "/" "\\\\"
           (string-trim (shell-command-to-string (concat "wslpath -w " (shell-quote-argument sound-path))))))
         (process-name "org-pomodoro-wsl-sound"))
    ;; Kill old process if any
    (when (get-process process-name)
      (kill-process process-name))
    ;; Start new process
    (start-process
     process-name nil
     "powershell.exe" "-c"
     (format "(New-Object Media.SoundPlayer '%s').PlaySync();" win-path))))

(defun org-pomodoro-play-sound (type)
  "Play an audio file specified by TYPE (:pomodoro, :short-break, :long-break)."
  (let* ((sound (org-pomodoro-sound type))
         (args (org-pomodoro-sound-args type)))
    (when (and sound org-pomodoro-play-sounds (file-exists-p sound))
      (cond
       ;; WSL: Use PowerShell to play sound
       ((org-pomodoro--running-in-wsl-p)
        (org-pomodoro--wsl-play-sound sound))

       ;; If sound-wav-play available and enabled
       ((fboundp 'sound-wav-play)
        (sound-wav-play sound))

       ;; Use configured audio player command and args
       ((and org-pomodoro-audio-player (not (string-empty-p org-pomodoro-audio-player)))
        (start-process-shell-command
         "org-pomodoro-audio-player" nil
         (mapconcat 'identity
                    `(,org-pomodoro-audio-player
                      ,@(delq nil (list args (shell-quote-argument (expand-file-name sound)))))
                    " ")))

       ;; Fallback beep if nothing else
       (t
        (beep)
        (message "No sound player found; beep instead."))))))

(defun org-pomodoro-maybe-play-sound (type)
  "Play an audio file specified by TYPE."
  (when (org-pomodoro-sound-p type)
    (org-pomodoro-play-sound type)))

(defun org-pomodoro-remaining-seconds ()
  "Return the number of seconds remaining in the current phase as a float.
Negative if the current phase is over."
 (float-time (time-subtract org-pomodoro-end-time (current-time))))

(defun org-pomodoro-format-seconds ()
  "Format the time remaining in the current phase with the format specified in
org-pomodoro-time-format."
  (format-seconds org-pomodoro-time-format
                  (if (eq org-pomodoro-state :overtime)
                      (- (org-pomodoro-remaining-seconds))
                    (org-pomodoro-remaining-seconds))))

;; (defun org-pomodoro-update-mode-line ()
;;   "Set the modeline accordingly to the current state."
;;   (let ((s (cl-case org-pomodoro-state
;;              (:pomodoro
;;               (propertize org-pomodoro-format 'face 'org-pomodoro-mode-line))
;;              (:overtime
;;               (propertize org-pomodoro-overtime-format
;;                           'face 'org-pomodoro-mode-line-overtime))
;;              (:short-break
;;               (propertize org-pomodoro-short-break-format
;;                           'face 'org-pomodoro-mode-line-break))
;;              (:long-break
;;               (propertize org-pomodoro-long-break-format
;;                           'face 'org-pomodoro-mode-line-break)))))
;;     (setq org-pomodoro-mode-line
;;           (when (and (org-pomodoro-active-p) (> (length s) 0))
;;             (list "[" (format s (org-pomodoro-format-seconds)) "] "))))
;;   (force-mode-line-update t))

(defun org-pomodoro-update-mode-line ()
  "Set the modeline accordingly to the current state."
  (let* ((fmt (cl-case org-pomodoro-state
                (:pomodoro org-pomodoro-format)
                (:overtime org-pomodoro-overtime-format)
                (:short-break org-pomodoro-short-break-format)
                (:long-break org-pomodoro-long-break-format)
                ;; For :none state or unknown states, use nil or empty string
                (t nil)))
         (fmt-str (and fmt (if (stringp fmt) fmt (format "%s" fmt)))))
    (if (or (null fmt-str)
            (string= fmt-str ""))
        (setq org-pomodoro-mode-line nil) ;; clear mode line if no format
      (let* ((face (cl-case org-pomodoro-state
                     (:pomodoro 'org-pomodoro-mode-line)
                     (:overtime 'org-pomodoro-mode-line-overtime)
                     (:short-break 'org-pomodoro-mode-line-break)
                     (:long-break 'org-pomodoro-mode-line-break)
                     (t nil))) ;; no face for none
             (formatted (format fmt-str (org-pomodoro-format-seconds)))
             (propertized (if face
                              (propertize formatted 'face face)
                            formatted)))
        (setq org-pomodoro-mode-line
              (when (and (org-pomodoro-active-p) propertized)
                (list "[" propertized "] ")))))
    (force-mode-line-update t)))


(defun org-pomodoro-kill ()
  "Kill the current timer, reset the phase and update the modeline."
  (org-pomodoro-killed))

(defun org-pomodoro-tick ()
  "A callback that is invoked by the running timer each second.
It checks whether we reached the duration of the current phase, when 't it
invokes the handlers for finishing."
  (when (and (not (org-pomodoro-active-p)) org-pomodoro-timer)
    (org-pomodoro-reset))
  (when (org-pomodoro-active-p)
    ;; The first element of a time value is the high-order part of the seconds
    ;; value. This is less than 0 if org-pomodoro-end-time is in the past of
    ;; the current-time.
    (when (< (org-pomodoro-remaining-seconds) 0)
      (cl-case org-pomodoro-state
        (:pomodoro (if org-pomodoro-manual-break
                       (org-pomodoro-overtime)
                     (org-pomodoro-finished)))
        (:short-break (org-pomodoro-short-break-finished))
        (:long-break (org-pomodoro-long-break-finished))))
    (run-hooks 'org-pomodoro-tick-hook)
    (org-pomodoro-update-mode-line)
    (when (and (member org-pomodoro-state org-pomodoro-ticking-sound-states)
               (equal (mod (truncate (org-pomodoro-remaining-seconds))
                           org-pomodoro-ticking-frequency)
                      0))
      (org-pomodoro-maybe-play-sound :tick))))

(defun org-pomodoro-set (state)
  "Set the org-pomodoro STATE."
  (setq org-pomodoro-state state
        org-pomodoro-end-time
        (cl-case state
          (:pomodoro (time-add (current-time) (* 60 org-pomodoro-length)))
          (:overtime (current-time))
          (:short-break (time-add (current-time) (* 60 org-pomodoro-short-break-length)))
          (:long-break (time-add (current-time) (* 60 org-pomodoro-long-break-length))))
        org-pomodoro-timer (run-with-timer t 1 'org-pomodoro-tick)))

(defun org-pomodoro-start (&optional state)
  "Start the `org-pomodoro` timer.
The argument STATE is optional.  The default state is `:pomodoro`."
  (when org-pomodoro-timer (cancel-timer org-pomodoro-timer))

  ;; add the org-pomodoro-mode-line to the global-mode-string
  (unless global-mode-string (setq global-mode-string '("")))
  (unless (memq 'org-pomodoro-mode-line global-mode-string)
    (setq global-mode-string (append global-mode-string
                                     '(org-pomodoro-mode-line))))

  (org-pomodoro-set (or state :pomodoro))

  (when (eq org-pomodoro-state :pomodoro)
    (org-pomodoro-maybe-play-sound :start)
    (run-hooks 'org-pomodoro-started-hook))
  (org-pomodoro-update-mode-line)
  (org-agenda-maybe-redo))

(defun org-pomodoro-reset ()
  "Reset the org-pomodoro state."
  (when org-pomodoro-timer
    (cancel-timer org-pomodoro-timer))
  (setq org-pomodoro-state :none
        org-pomodoro-end-time nil)
  (org-pomodoro-update-mode-line)
  (org-agenda-maybe-redo))

(defun org-pomodoro-notify (title message)
  "Send a notification with TITLE and MESSAGE using `alert'."
  (alert message :title title :category 'org-pomodoro))

;; Handlers for pomodoro events.

(defun org-pomodoro-overtime ()
  "Is invoked when the time for a pomodoro runs out.
Notify the user that the pomodoro should be finished by calling ‘org-pomodoro’"
  (org-pomodoro-maybe-play-sound :overtime)
  (org-pomodoro-notify "Pomodoro completed. Now on overtime!" "Start break by calling ‘org-pomodoro’")
  (org-pomodoro-start :overtime)
  (org-pomodoro-update-mode-line)
  (run-hooks 'org-pomodoro-overtime-hook))

;; (defun org-pomodoro-finished ()
;;   "Is invoked when a pomodoro was finished successfully.
;; This may send a notification, play a sound and start a pomodoro break."
;;   (unless org-pomodoro-clock-break
;;       (org-clock-out nil t))
;;   (org-pomodoro-maybe-play-sound :pomodoro)
;;   (setq org-pomodoro-count (+ org-pomodoro-count 1))
;;   (if (zerop (mod org-pomodoro-count org-pomodoro-long-break-frequency))
;;       (org-pomodoro-start :long-break)
;;     (org-pomodoro-start :short-break))
;;   (org-pomodoro-notify "Pomodoro completed!" "Time for a break.")
;;   (org-pomodoro-update-mode-line)
;;   (org-agenda-maybe-redo)
;;   (run-hooks 'org-pomodoro-finished-hook))

;; (defun org-pomodoro-finished ()
;;   "Is invoked when a pomodoro was finished successfully.
;; This may send a notification, play a sound and start a pomodoro break."
;;   (when (org-clocking-p)
;;     (if org-pomodoro-clock-break
;;         (org-clock-out nil t)
;;       (org-clock-out nil t))) ;; force stop if not clocking break
;;   (org-pomodoro-maybe-play-sound :pomodoro)
;;   (setq org-pomodoro-count (+ org-pomodoro-count 1))
;;   (if (zerop (mod org-pomodoro-count org-pomodoro-long-break-frequency))
;;       (org-pomodoro-start :long-break)
;;     (org-pomodoro-start :short-break))
;;   (org-pomodoro-notify "Pomodoro completed!" "Time for a break.")
;;   (org-pomodoro-update-mode-line)
;;   (org-agenda-maybe-redo)
;;   (run-hooks 'org-pomodoro-finished-hook))

(defun org-pomodoro-finished ()
  "Is invoked when a pomodoro was finished successfully.
This may send a notification, play a sound and start a pomodoro break."
  (unless org-pomodoro-clock-break
      (org-clock-out nil t))
  (org-pomodoro-maybe-play-sound :pomodoro)
  (setq org-pomodoro-count (+ org-pomodoro-count 1))
  (if (zerop (mod org-pomodoro-count org-pomodoro-long-break-frequency))
      (org-pomodoro-start :long-break)
    (org-pomodoro-start :short-break))
  (org-pomodoro-notify "Pomodoro completed!" "Time for a break.")
  (org-pomodoro-update-mode-line)
  (org-agenda-maybe-redo)
  (run-hooks 'org-pomodoro-finished-hook))

(defun org-pomodoro-killed ()
  "Is invoked when a pomodoro was killed.
This may send a notification, play a sound and adds log."
  (org-pomodoro-reset)
  (org-pomodoro-notify "Pomodoro killed." "One does not simply kill a pomodoro!")
  (org-pomodoro-maybe-play-sound :killed)
  (when (org-clocking-p)
    (if org-pomodoro-keep-killed-pomodoro-time
        (org-clock-out nil t)
      (org-clock-cancel)))
  (run-hooks 'org-pomodoro-killed-hook))

;; (defun org-pomodoro-short-break-finished ()
;;   "Is invoked when a short break is finished.
;; This may send a notification and play a sound."
;;   (when org-pomodoro-clock-break
;;     (org-clock-out nil t))
;;   (org-pomodoro-reset)
;;   (org-pomodoro-notify "Short break finished." "Ready for another pomodoro?")
;;   (org-pomodoro-maybe-play-sound :short-break)
;;   (run-hooks 'org-pomodoro-break-finished-hook 'org-pomodoro-short-break-finished-hook))

;; (defun org-pomodoro-long-break-finished ()
;;   "Is invoked when a long break is finished.
;; This may send a notification and play a sound."
;;   (when org-pomodoro-clock-break
;;     (org-clock-out nil t))
;;   (org-pomodoro-reset)
;;   (org-pomodoro-notify "Long break finished." "Ready for another pomodoro?")
;;   (org-pomodoro-maybe-play-sound :long-break)
;;   (run-hooks 'org-pomodoro-break-finished-hook 'org-pomodoro-long-break-finished-hook))

;; (defun org-pomodoro-short-break-finished ()
;;   "Is invoked when a short break is finished.
;; If `org-pomodoro-auto-start` is non-nil, clock out break, then clock
;; into the original task and start a new pomodoro.
;; Otherwise, reset the state and prompt the user."
;;   (when org-pomodoro-clock-break
;;     (org-clock-out nil t))
;;   (org-pomodoro-maybe-play-sound :short-break)
;;   (run-hooks 'org-pomodoro-break-finished-hook 'org-pomodoro-short-break-finished-hook)
;;   (if org-pomodoro-auto-start
;;       (progn
;;         ;; Ensure any open clock is closed before starting the new one
;;         (when (org-clocking-p)
;;           (org-clock-out nil t))
;;         (org-pomodoro-notify "Short break finished." "Starting another pomodoro.")
;;         (when org-pomodoro-original-task-marker
;;           (org-with-point-at org-pomodoro-original-task-marker
;;             (org-clock-in)))
;;         (org-pomodoro-start :pomodoro))
;;     (org-pomodoro-reset)
;;     (org-pomodoro-notify "Short break finished." "Ready for another pomodoro?")))

;; (defun org-pomodoro-long-break-finished ()
;;   "Is invoked when a long break is finished.
;; If `org-pomodoro-auto-start` is non-nil, clock out break, then clock
;; into the original task and start a new pomodoro.
;; Otherwise, reset the state and prompt the user."
;;   (when org-pomodoro-clock-break
;;     (org-clock-out nil t))
;;   (org-pomodoro-maybe-play-sound :long-break)
;;   (run-hooks 'org-pomodoro-break-finished-hook 'org-pomodoro-long-break-finished-hook)
;;   (if org-pomodoro-auto-start
;;       (progn
;;         ;; Ensure any open clock is closed before starting the new one
;;         (when (org-clocking-p)
;;           (org-clock-out nil t))
;;         (org-pomodoro-notify "Long break finished." "Starting another pomodoro.")
;;         (when org-pomodoro-original-task-marker
;;           (org-with-point-at org-pomodoro-original-task-marker
;;             (org-clock-in)))
;;         (org-pomodoro-start :pomodoro))
;;     (org-pomodoro-reset)
;;     (org-pomodoro-notify "Long break finished." "Ready for another pomodoro?")))

;; (defun org-pomodoro-short-break-finished ()
;;   "Is invoked when a short break is finished.
;; If `org-pomodoro-auto-start` is non-nil, clock out break, then clock
;; into the original task and start a new pomodoro.
;; Otherwise, reset the state and prompt the user."
;;   (when (org-clocking-p)
;;     (org-clock-out nil t)) ;; Always clock out after break

;;   (org-pomodoro-maybe-play-sound :short-break)
;;   (run-hooks 'org-pomodoro-break-finished-hook 'org-pomodoro-short-break-finished-hook)

;;   (if org-pomodoro-auto-start
;;       (progn
;;         (org-pomodoro-notify "Short break finished." "Starting another pomodoro.")
;;         (when org-pomodoro-original-task-marker
;;           (org-with-point-at org-pomodoro-original-task-marker
;;             (org-clock-in)))
;;         (org-pomodoro-start :pomodoro))
;;     (org-pomodoro-reset)
;;     (org-pomodoro-notify "Short break finished." "Ready for another pomodoro?")))

;; (defun org-pomodoro-long-break-finished ()
;;   "Is invoked when a long break is finished.
;; If `org-pomodoro-auto-start` is non-nil, clock out break, then clock
;; into the original task and start a new pomodoro.
;; Otherwise, reset the state and prompt the user."
;;   (when (org-clocking-p)
;;     (org-clock-out nil t)) ;; Always clock out after break

;;   (org-pomodoro-maybe-play-sound :long-break)
;;   (run-hooks 'org-pomodoro-break-finished-hook 'org-pomodoro-long-break-finished-hook)

;;   (if org-pomodoro-auto-start
;;       (progn
;;         (org-pomodoro-notify "Long break finished." "Starting another pomodoro.")
;;         (when org-pomodoro-original-task-marker
;;           (org-with-point-at org-pomodoro-original-task-marker
;;             (org-clock-in)))
;;         (org-pomodoro-start :pomodoro))
;;     (org-pomodoro-reset)
;;     (org-pomodoro-notify "Long break finished." "Ready for another pomodoro?")))

(defun org-pomodoro-short-break-finished ()
  "Is invoked when a short break is finished.
If org-pomodoro-auto-start is non-nil, clock out break, then clock
into the original task and start a new pomodoro.
Otherwise, reset the state and prompt the user."
  (when org-pomodoro-clock-break
    (org-clock-out nil t))
  (org-pomodoro-maybe-play-sound :short-break)
  (run-hooks 'org-pomodoro-break-finished-hook
	     'org-pomodoro-short-break-finished-hook)
  (if org-pomodoro-auto-start
      (progn
        ;; Ensure any open clock is closed before starting the new one
        (when (org-clocking-p)
          (org-clock-out nil t))
        (org-pomodoro-notify "Short break finished." "Starting another pomodoro.")
        (when org-pomodoro-original-task-marker
          (org-with-point-at org-pomodoro-original-task-marker
            (org-clock-in)))
        (org-pomodoro-start :pomodoro))
    (org-pomodoro-reset)
    (org-pomodoro-notify "Short break finished." "Ready for another pomodoro?")))

(defun org-pomodoro-long-break-finished ()
  "Is invoked when a long break is finished.
If org-pomodoro-auto-start is non-nil, clock out break, then clock
into the original task and start a new pomodoro.
Otherwise, reset the state and prompt the user."
  (when org-pomodoro-clock-break
    (org-clock-out nil t))
  (org-pomodoro-maybe-play-sound :long-break)
  (run-hooks 'org-pomodoro-break-finished-hook
	     'org-pomodoro-long-break-finished-hook)
  (if org-pomodoro-auto-start
      (progn
        ;; Ensure any open clock is closed before starting the new one
        (when (org-clocking-p)
          (org-clock-out nil t))
        (org-pomodoro-notify "Long break finished." "Starting another pomodoro.")
        (when org-pomodoro-original-task-marker
          (org-with-point-at org-pomodoro-original-task-marker
            (org-clock-in)))
        (org-pomodoro-start :pomodoro))
    (org-pomodoro-reset)
    (org-pomodoro-notify "Long break finished." "Ready for another pomodoro?")))



(defun org-pomodoro-extend-last-clock ()
  "Extends last clock to `current-time'."
  (interactive)
  (save-window-excursion
    (org-clock-goto)
    (when (re-search-forward ":LOGBOOK:" (save-excursion (outline-next-heading)) t)
      (org-hide-drawer-toggle 'hide))
    (let ((last-clock (car org-clock-history)))
      (switch-to-buffer (marker-buffer last-clock))
      (goto-char last-clock)
      (let ((item-end (save-excursion (org-end-of-subtree t))))
        (when (re-search-forward "CLOCK: \\(\\[.*?\\]\\)" item-end t)
          (kill-line)
          (org-clock-clock-out
           (cons (copy-marker (match-end 1) t)
                 (org-time-string-to-time (match-string 1)))))))))

(defvar org-pomodoro-paused-time nil
  "Time when pomodoro was paused.")

(defvar org-pomodoro-paused-p nil
  "Non-nil if the pomodoro is currently paused.")

(defvar org-pomodoro-paused-task-marker nil
  "Marker to remember the task that was active when pausing.")

(defun org-pomodoro-pause ()
  "Pause the current Pomodoro session."
  (interactive)
  (unless org-pomodoro-paused-p
    ;; Save the paused time
    (setq org-pomodoro-paused-time (current-time))

    ;; Save the current task position if clock is active and we're not on a break
    (when (and (org-clock-is-active)
               (or (not (memq org-pomodoro-state '(:short-break :long-break)))
                   org-pomodoro-clock-break))
      (setq org-pomodoro-paused-task-marker (copy-marker org-clock-marker))
      (org-clock-out))

    ;; Cancel timer
    (when (timerp org-pomodoro-timer)
      (cancel-timer org-pomodoro-timer)
      (setq org-pomodoro-timer nil))

    ;; Mark as paused
    (setq org-pomodoro-paused-p t)
    (message "Pomodoro paused.")))

(defun org-pomodoro-resume ()
  "Resume the Pomodoro session from pause."
  (interactive)
  (when org-pomodoro-paused-p
    ;; Adjust end time
    (when org-pomodoro-paused-time
      (let* ((paused-delta (float-time (time-subtract (current-time) org-pomodoro-paused-time))))
        (setq org-pomodoro-end-time (time-add org-pomodoro-end-time paused-delta))))
    ;; Resume task clock if appropriate
    (when (and org-pomodoro-paused-task-marker
               (marker-buffer org-pomodoro-paused-task-marker)
               ;; Only clock back in if not on break or clocking breaks is enabled
               (or (not (memq org-pomodoro-state '(:short-break :long-break)))
                   org-pomodoro-clock-break))
      (org-with-point-at org-pomodoro-paused-task-marker
        (org-clock-in)))
    ;; Restart the timer
    (setq org-pomodoro-timer
          (run-at-time t 1 'org-pomodoro-tick))
    ;; Clear paused state
    (setq org-pomodoro-paused-p nil
          org-pomodoro-paused-time nil)
    (message "Pomodoro resumed.")))

(defun org-pomodoro-toggle-pause ()
  "Toggle between pausing and resuming Pomodoro, even on breaks."
  (interactive)
  (if org-pomodoro-paused-p
      (org-pomodoro-resume)
    (org-pomodoro-pause)))



;;;###autoload
(defun org-pomodoro (&optional arg)
  "Start a new pomodoro or stop the current one.

When no timer is running for `org-pomodoro` a new pomodoro is started and
the current task is clocked in. Otherwise EMACS will ask whether we'd like to
kill the current timer, this may be a break or a running pomodoro."
  (interactive "P")

  ;; Prompt for reset if session expired
  (when (and org-pomodoro-last-clock-in
             org-pomodoro-expiry-time
             (org-pomodoro-expires-p)
             (y-or-n-p "Reset pomodoro count? "))
    (setq org-pomodoro-count 0))

  ;; Save marker to original task if we’re starting fresh
  (setq org-pomodoro-last-clock-in (current-time))
  (unless (org-pomodoro-active-p)
    (setq org-pomodoro-original-task-marker
          (cond
           ((eq major-mode 'org-agenda-mode)
            (org-get-at-bol 'org-hd-marker))
           ((memq major-mode '(org-mode org-journal-mode))
            (point-marker))
           (t nil))))

  (cond
   ;; Finish an overtime pomodoro
   ((and (org-pomodoro-active-p) (eq org-pomodoro-state :overtime))
    (org-pomodoro-finished))

   ;; Prompt to kill a running pomodoro or break
   ((org-pomodoro-active-p)
    (if (or (not org-pomodoro-ask-upon-killing)
            (y-or-n-p "There is already a running timer. Would you like to stop it? "))
        (org-pomodoro-kill)
      (message "Alright, keep up the good work!")))

   ;; Otherwise, start and clock in
   (t
    (cond
     ((equal arg '(4))
      (let ((current-prefix-arg '(4)))
        (call-interactively 'org-clock-in)))
     ((equal arg '(16))
      (call-interactively 'org-clock-in-last))
     ((memq major-mode '(org-mode org-journal-mode))
      (call-interactively 'org-clock-in))
     ((eq major-mode 'org-agenda-mode)
      (org-with-point-at (org-get-at-bol 'org-hd-marker)
        (call-interactively 'org-clock-in)))
     (t (let ((current-prefix-arg '(4)))
          (call-interactively 'org-clock-in))))
    (org-pomodoro-start :pomodoro))))

(provide 'org-pomodoro)

;;; org-pomodoro.el ends here
