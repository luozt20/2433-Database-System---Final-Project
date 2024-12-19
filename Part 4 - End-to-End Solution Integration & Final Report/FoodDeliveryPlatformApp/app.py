from flask import Flask, render_template, request, redirect, url_for, session
import sqlite3

app = Flask(__name__)
app.secret_key = 'your_secret_key'
DB_PATH = "FoodDeliveryPlatform.db"


def query_db(query, args=(), one=False):
    """Helper function to interact with the database."""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()
    cur.execute(query, args)
    rv = cur.fetchall()
    conn.commit()
    conn.close()
    return (rv[0] if rv else None) if one else rv


@app.route('/')
def home():
    restaurants = query_db("SELECT * FROM Restaurant")
    return render_template('home.html', restaurants=restaurants)


@app.route('/restaurant/<int:restaurant_id>')
def restaurant_menu(restaurant_id):
    menu_items = query_db("""
        SELECT MenuItem.*
        FROM MenuItem
        JOIN Menu ON MenuItem.MenuID = Menu.MenuID
        WHERE Menu.RestaurantID = ?
    """, (restaurant_id,))
    restaurant = query_db("SELECT * FROM Restaurant WHERE RestaurantID = ?", (restaurant_id,), one=True)
    return render_template('menu.html', menu_items=menu_items, restaurant=restaurant)


@app.route('/order/<int:menu_item_id>', methods=["POST"])
def place_order(menu_item_id):
    if 'user_id' not in session:
        return redirect(url_for('login'))
    user_id = session['user_id']
    menu_item = query_db("SELECT * FROM MenuItem WHERE MenuItemID = ?", (menu_item_id,), one=True)
    if menu_item:
        total_price = menu_item["Price"]
        query_db("""
            INSERT INTO `Order` (UserID, RestaurantID, OrderStatus, TotalAmount, PaymentStatus)
            VALUES (?, ?, 'Placed', ?, 'Pending')
        """, (user_id, menu_item["MenuID"], total_price))
        return redirect(url_for('order_success'))
    return "Error placing order", 400


@app.route('/cart')
def cart():
    if 'user_id' not in session:
        return redirect(url_for('login'))
    user_id = session['user_id']
    cart_items_query = query_db("""
        SELECT OrderItem.OrderItemID AS id, MenuItem.Name AS name, OrderItem.Quantity AS quantity, 
               OrderItem.TotalPrice AS total_price, MenuItem.Price AS price
        FROM OrderItem
        JOIN MenuItem ON OrderItem.MenuItemID = MenuItem.MenuItemID
        JOIN `Order` ON OrderItem.OrderID = `Order`.OrderID
        WHERE `Order`.UserID = ? AND `Order`.OrderStatus = 'Placed'
    """, (user_id,))
    # Convert sqlite3.Row objects to dictionaries
    cart_items = [dict(item) for item in cart_items_query]
    cart_total = sum(item['total_price'] for item in cart_items)
    return render_template('cart.html', cart_items=cart_items, cart_total=cart_total)

@app.route('/cart/remove/<int:item_id>', methods=["POST"])
def remove_from_cart(item_id):
    if 'user_id' not in session:
        return redirect(url_for('login'))
    user_id = session['user_id']
    # Delete the specific item from the cart
    query_db("""
        DELETE FROM OrderItem
        WHERE OrderItemID = ? AND OrderID IN (
            SELECT OrderID FROM `Order`
            WHERE UserID = ? AND OrderStatus = 'Placed'
        )
    """, (item_id, user_id))
    return redirect(url_for('cart'))

@app.route('/add-to-cart/<int:menu_item_id>', methods=["POST"])
def add_to_cart(menu_item_id):
    if 'user_id' not in session:
        return redirect(url_for('login'))
    user_id = session['user_id']

    # Check if there's an active order for the user
    order = query_db("""
        SELECT OrderID FROM `Order` 
        WHERE UserID = ? AND OrderStatus = 'Placed'
    """, (user_id,), one=True)

    if not order:
        # Create a new order if none exists
        restaurant_id = query_db("""
            SELECT Menu.RestaurantID 
            FROM MenuItem
            JOIN Menu ON MenuItem.MenuID = Menu.MenuID
            WHERE MenuItem.MenuItemID = ?
        """, (menu_item_id,), one=True)["RestaurantID"]

        query_db("""
            INSERT INTO `Order` (UserID, RestaurantID, OrderStatus, TotalAmount, PaymentStatus)
            VALUES (?, ?, 'Placed', 0, 'Pending')
        """, (user_id, restaurant_id))
        order = query_db("""
            SELECT OrderID FROM `Order` 
            WHERE UserID = ? AND OrderStatus = 'Placed'
        """, (user_id,), one=True)

    # Check if the item is already in the cart
    cart_item = query_db("""
        SELECT OrderItemID, Quantity FROM OrderItem 
        WHERE OrderID = ? AND MenuItemID = ?
    """, (order['OrderID'], menu_item_id), one=True)

    if cart_item:
        # Update quantity if the item is already in the cart
        query_db("""
            UPDATE OrderItem 
            SET Quantity = Quantity + 1, TotalPrice = TotalPrice + (SELECT Price FROM MenuItem WHERE MenuItemID = ?)
            WHERE OrderItemID = ?
        """, (menu_item_id, cart_item['OrderItemID']))
    else:
        # Add the new item to the cart
        query_db("""
            INSERT INTO OrderItem (OrderID, MenuItemID, Quantity, ItemPrice, TotalPrice)
            VALUES (?, ?, 1, (SELECT Price FROM MenuItem WHERE MenuItemID = ?), (SELECT Price FROM MenuItem WHERE MenuItemID = ?))
        """, (order['OrderID'], menu_item_id, menu_item_id, menu_item_id))

    return redirect(url_for('restaurant_menu', restaurant_id=query_db("""
        SELECT Menu.RestaurantID 
        FROM MenuItem
        JOIN Menu ON MenuItem.MenuID = Menu.MenuID
        WHERE MenuItem.MenuItemID = ?
    """, (menu_item_id,), one=True)["RestaurantID"]))


@app.route('/account')
def account():
    if 'user_id' not in session:
        return redirect(url_for('login'))
    user_id = session['user_id']
    user = query_db("SELECT * FROM IndividualUser WHERE UserID = ?", (user_id,), one=True)
    return render_template('account.html', user=user)


@app.route('/login', methods=["GET", "POST"])
def login():
    if request.method == "POST":
        email = request.form['email']
        password = request.form['password']
        user = query_db("""
            SELECT * FROM IndividualUser WHERE Email = ? AND Password = ?
        """, (email, password), one=True)
        if user and user["UserType"] == "Customer":
            session['user_id'] = user["UserID"]
            return redirect(url_for('home'))
        return "Invalid credentials or not a customer!", 401
    return render_template('login.html')

@app.route('/logout')
def logout():
    # Clear the session to log out the user
    session.clear()
    # Redirect to the login page
    return redirect(url_for('login'))

@app.route('/order-success')
def order_success():
    return render_template('order_success.html')

@app.route('/checkout', methods=["GET", "POST"])
def checkout():
    if 'user_id' not in session:
        return redirect(url_for('login'))
    user_id = session['user_id']

    if request.method == "POST":
        # Redirect to the order success page without updating the order
        return redirect(url_for('checkout_success'))

    # Fetch cart details for display
    cart_items = query_db("""
        SELECT MenuItem.Name, OrderItem.Quantity, OrderItem.TotalPrice
        FROM OrderItem
        JOIN MenuItem ON OrderItem.MenuItemID = MenuItem.MenuItemID
        JOIN `Order` ON OrderItem.OrderID = `Order`.OrderID
        WHERE `Order`.UserID = ? AND `Order`.OrderStatus = 'Placed'
    """, (user_id,))
    cart_total = sum(item['TotalPrice'] for item in cart_items)

    return render_template('checkout.html', cart_items=cart_items, cart_total=cart_total)


@app.route('/checkout-success')
def checkout_success():
    return render_template('checkout_success.html')

if __name__ == '__main__':
    app.run(debug=True)