#!/usr/bin/ruby
# -*- coding: utf-8 -*-
require 'rubygems'
require 'net/ssh'
require 'net/ssh/shell'
require 'net/scp'
require 'yaml'

module  Routine
  def config
    YAML::load_file('config.yml')
  end
end

#== アルケミアサーバーに入り、動画変換プログラムを実行し
#   コンテンツサーバーに転送する
class Routine::Alchemia
  class App
    class << self
      include Routine
      def run
        alchemia = config['account']['alchemia']
        Net::SSH.start(alchemia['host'], alchemia['user'], :password => alchemia['password']) do |ssh|

          # 処理対象のディレクトリを特定
          dirs = Array.new
          ls = ssh.exec! 'ls -l'
          ls.each_line do |line|
            entry = line.split(' ').last
            if entry =~ /\d{6}app/
              dirs << entry
            end
          end

          if dirs.max.nil?
            puts '処理対象のディレクトリがありませんでした'
            puts 'プログラムを終了します'
            return
          end

          # ファイル転送
          okimax = config['account']['okimax']
          command =  sprintf("scp -r ~/%s/* %s@%s:~/alcheapk/", dirs.max, okimax['user'], okimax['host'])
          puts command
          ssh.open_channel do |channel|
            channel.request_pty
            channel.exec command do |ch, success|
              channel.on_data do |ch, data|
                puts data
                if data =~ /password/
                  puts 'send password'
                  channel.send_data okimax['password']
                  channel.send_data "\n"
                end
              end
              channel.on_close { |ch| puts 'scp finished.' }
            end
          end

          ssh.loop
        end
      end
    end
  end

  class << self # class methods
    include Routine
    def run
      alchemia = config['account']['alchemia']
      Net::SSH.start(alchemia['host'], alchemia['user'], :password => alchemia['password']) do |ssh|

        # 処理対象のディレクトリを探し動画変換を実行
        dirs = Array.new
        ls = ssh.exec! 'ls -l'
        ls.each_line do |line|
          entry = line.split(' ').last
          if entry =~ /\d{6}/
            dirs << entry
          end
        end

        if dirs.max.nil?
          puts '処理対象のディレクトリがありませんでした'
          puts 'プログラムを終了します'
          return
        end

        command = "php MP4Box.php #{dirs.max}"
        puts command
        ssh.exec! command

        # sun.oki-max.netに動画を転送する
        okimax = config['account']['okimax']
        command =  sprintf("scp -r ~/tmp/* %s@%s:~/video/", okimax['user'], okimax['host'])
        puts command
        ssh.open_channel do |channel|
          channel.request_pty
          channel.exec command do |ch, success|
            channel.on_data do |ch, data|
              puts data
              if data =~ /password/
                puts 'send password'
                channel.send_data okimax['password']
                channel.send_data "\n"
              end
            end
            channel.on_close { |ch| puts 'scp finished.' }
          end
        end

        ssh.loop
      end
    end
  end
end

#== コンテンツサーバーにファイル転送し
#   登録プログラムを実行する
class Routine::SunOkimax
  class << self
    include Routine
    # データファイル(CSV)をアップロード
    def upload
      puts 'upload alche.csv'
      scp_start { |scp| scp.upload!('alche.csv', 'bin/') }
    end

    def upload_apk
      puts 'upload alche.apk.csv'
      scp_start { |scp| scp.upload!('alche.apk.csv', 'bin/apk/alche.csv') }
    end

    # 動画出力先を空にする
    def clean
      puts 'rm -rf video/*'
      ssh_start { |ssh| ssh.exec! 'rm -rf video/*' }
    end

    def clean_apk
      puts 'rm -rf alcheapk/*'
      ssh_start { |ssh| ssh.exec! 'rm -rf alcheapk/*' }
    end

    # 動画登録
    def run
      puts 'php alche.php'
      ssh_start do |ssh|
        ssh.shell do |sh|
          sh.execute 'cd bin'
          sh.execute 'php alche.php'
          sh.execute 'exit'
        end
        ssh.loop
      end
    end

    def run_apk
      ssh_start do |ssh|
        ssh.shell do |sh|
          sh.execute 'cd bin/apk'
          sh.execute 'php alche.php'
          sh.execute 'php alche_media.php'
          sh.execute 'exit'
        end
        ssh.loop
      end
    end

    private

    def okimax
      config['account']['okimax']
    end

    def ssh_start
      Net::SSH.start(okimax['host'], okimax['user'], :password => okimax['password']) do |ssh|
        yield ssh
      end
    end

    def scp_start
      Net::SCP.start(okimax['host'], okimax['user'], :password => okimax['password']) do |scp|
        yield scp
      end
    end
  end

end

#== Shift_JISのCSVファイルを読み込んでヘッダ以外をUTF8に変換して出力
class Routine::Local
  class << self
    def convert(readfile, writefile)
      rfp = File.open(readfile, 'r', :external_encoding => Encoding::Shift_JIS, :internal_encoding => Encoding::UTF_8)
      wfp = File.open(writefile, 'w', :external_encoding => Encoding::UTF_8)
      rfp.gets
      while line = rfp.gets
        wfp.write(line)
      end
    end
  end

  class Movie < Routine::Local
    class << self
      def convert
        super('alche.origin.csv', 'alche.csv')
      end
    end
  end

  class App < Routine::Local
    class << self
      def convert
        super('alche.apk.origin.csv', 'alche.apk.csv')
      end
    end
  end
end

# 動画登録処理
Routine::Local::Movie::convert
Routine::SunOkimax::clean
Routine::SunOkimax::upload
Routine::Alchemia::run
Routine::SunOkimax::run

# アプリ登録処理
Routine::Local::App.convert
Routine::SunOkimax.clean_apk
Routine::SunOkimax.upload_apk
Routine::Alchemia::App.run
Routine::SunOkimax.run_apk

__END__
