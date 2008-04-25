require File.dirname(__FILE__) + '/oos'

class OosWithShoes < Shoes
  url '/', :index
  url '/save/(\\d+)', :save
  
  def index
    @oos = Oos.instance    
    unless @oos.credentials
      @oos.temp_token
      login
    else
      contacts
    end
    timer(30) do
      @oos.update_contacts
      visit("/")
    end
  end
  
  def login
    flow :margin => 5 do
      background '#e6e6e6', :radius => 12 
      stack :width => '100%', :margin => 5 do
        subtitle "11870.com on shoes"
      end
      stack :width => '100%', :margin => 5 do
        para "Para poder usar OosWithShoes tienes que darle acceso a tu cuenta de 11870.com.\n"
      end
      stack :width => '100%', :margin => 5 do
        para "Introduce aqui el email con el que te has registrado en 11870.com\n"
        @mail = edit_line(:width => 250, :text => 'david.calavera@11870.com')

        para "\nPulsa el botón y cuando termines en 11870.com confirmalo en la ventana emergente.\n"
        button "Dar acceso" do
          @oos.user_mail = @mail.text
          visit("http://#{@oos.host}/manage-api/create-token?tempToken=#{@oos.temp_token}&privilege=WRITE")
          answer confirm("Cuando me hayas dado acceso en 11870.com pulsa el botón de 'Aceptar'")         
        end
        para ""
      end
    end
  end
  
  def contacts    
    @oos.contacts.each do |contact|
      flow :margin => 5 do
      background '#e6e6e6', :radius => 12
        stack :width => '100%', :margin => 5 do         
          latest_service = contact[:contact][:services][:latest]

          para "#{contact[:contact][:nick]} se ha guardado:\n",
            "\t", strong(latest_service[:name]), "\t", 
            link("Guardar", :click => 
              "/save/#{latest_service[:oos_id]}")
          if (latest_service[:review_title] ||
              latest_service[:review_content])

            if latest_service[:review_title]
              para "\t", contact[:contact][:services][:latest][:review_title]
            end
            if latest_service[:review_content]
              para "\t", contact[:contact][:services][:latest][:review_content][0,50], "..."
            end             
          end
        end
      end
      
    end   
  end
  
  def save(id)
    @oos = Oos.instance    
    service = @oos.search_service(id)
    flow :margin => 5 do
      background '#e6e6e6', :radius => 12
      
      stack :width => '100%', :margin => 10 do      
        para "Vas a guardar ", strong(service[:name]), "\n",
           "(SE GUARDARA EN PRIVADO)\n", 
           link("Ver lo que hacen tus contactos", :click => "/")
      end
      stack :width => '100%', :margin => 10 do
        para "Título del comentario:\n"
        @title = edit_line(:width => 250)

        para "Contenido:\n"
        @content = edit_box("", :width => 250, :height => 250)

        button "Guardar" do          
          @saved = @oos.save(service[:oos_id], service[:name], 
            @title.text, @content.text)
          if (@saved == true)
            alert("guardado correctamente")
          else
            alert("ha ocurrido un error")
          end
        end
        para ""
      end
    end
  end
  
  def answer(v)    
    if (v.inspect == 'true')
      @oos.auth_token
      visit("/")
    end
  end
end

Shoes.app :width => 480, :height => 550, :resizable => false